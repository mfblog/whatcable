/*
 * 33_displayport_capability.c - DisplayPort link + monitor capability.
 *
 * Enumerates IOPortTransportStateDisplayPort (the node WhatCable's display
 * dimension reads) and dumps the fields that drive the weakest-link verdict:
 * the negotiated link (rate, lanes, max lanes), whether it is tunnelled,
 * the downstream-facing-port / adapter type and BranchDeviceID, the
 * NominalSignalingFrequenciesHz array (whose meaning, current rate vs
 * trainable ceiling, we are still confirming), and the monitor's FULL EDID
 * (base block plus any CTA-861 extension).
 *
 * Why a dedicated probe rather than reusing 26: probe 26 is an exploratory
 * grab-bag that catches this node only by a name wildcard, reads it with the
 * bulk IORegistryEntryCreateCFProperties (the issue #181 mid-teardown crash
 * path), and truncates CFData at 64 bytes, which mangles the 256-byte EDID.
 * This one reads per-key (safe) and prints the full EDID so the CTA
 * extension survives.
 *
 * Compile: clang -framework IOKit -framework CoreFoundation -o 33_displayport_capability 33_displayport_capability.c
 */

#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Read one property by key. Per-key, never the bulk all-properties fetch,
// so a service being torn down mid-read can't abort us (issue #181).
static CFTypeRef readKey(io_service_t svc, const char *key) {
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    if (!k) return NULL;
    CFTypeRef v = IORegistryEntryCreateCFProperty(svc, k, kCFAllocatorDefault, 0);
    CFRelease(k);
    return v; // caller releases
}

static void printValue(const char *label, CFTypeRef v) {
    if (!v) { printf("  %s = (absent)\n", label); return; }
    CFTypeID tid = CFGetTypeID(v);
    if (tid == CFStringGetTypeID()) {
        char buf[1024];
        if (CFStringGetCString(v, buf, sizeof(buf), kCFStringEncodingUTF8))
            printf("  %s = \"%s\"\n", label, buf);
        else
            printf("  %s = (unprintable string)\n", label);
    } else if (tid == CFNumberGetTypeID()) {
        long long n = 0;
        CFNumberGetValue(v, kCFNumberLongLongType, &n);
        printf("  %s = %lld\n", label, n);
    } else if (tid == CFBooleanGetTypeID()) {
        printf("  %s = %s\n", label, CFBooleanGetValue(v) ? "true" : "false");
    } else if (tid == CFArrayGetTypeID()) {
        CFIndex c = CFArrayGetCount(v);
        printf("  %s = [", label);
        for (CFIndex i = 0; i < c; i++) {
            CFTypeRef e = CFArrayGetValueAtIndex(v, i);
            if (e && CFGetTypeID(e) == CFNumberGetTypeID()) {
                long long n = 0;
                CFNumberGetValue(e, kCFNumberLongLongType, &n);
                printf("%s%lld", i ? ", " : "", n);
            }
        }
        printf("]\n");
    } else if (tid == CFSetGetTypeID()) {
        // NominalSignalingFrequenciesHz is a CFSet of CFNumbers (a set of
        // signalling rates, which is why it renders like an array in ioreg).
        CFIndex c = CFSetGetCount(v);
        const void **vals = malloc(c * sizeof(void *));
        printf("  %s = {", label);
        if (vals) {
            CFSetGetValues(v, vals);
            for (CFIndex i = 0; i < c; i++) {
                CFTypeRef e = vals[i];
                if (e && CFGetTypeID(e) == CFNumberGetTypeID()) {
                    long long n = 0;
                    CFNumberGetValue(e, kCFNumberLongLongType, &n);
                    printf("%s%lld", i ? ", " : "", n);
                }
            }
            free(vals);
        }
        printf("}\n");
    } else if (tid == CFDataGetTypeID()) {
        CFIndex len = CFDataGetLength(v);
        const UInt8 *src = CFDataGetBytePtr(v);
        // EDID carries the monitor's serial number: base-block bytes 12-15
        // and any 0xFF "display product serial number" descriptor. The test
        // kit promises no serial numbers, so redact those before printing.
        // Capability data (timings, the CTA-861 extension) is kept intact.
        int isEDID = (strstr(label, "EDID") != NULL);
        int redactedOk = 0;
        UInt8 *redacted = NULL;
        if (isEDID && len >= 128) {
            redacted = malloc(len);
            if (redacted) {
                memcpy(redacted, src, len);
                redacted[12] = redacted[13] = redacted[14] = redacted[15] = 0;
                const int slots[4] = {54, 72, 90, 108};
                for (int s = 0; s < 4; s++) {
                    int o = slots[s];
                    if (redacted[o] == 0 && redacted[o + 1] == 0 &&
                        redacted[o + 2] == 0 && redacted[o + 3] == 0xff) {
                        for (int j = 5; j < 18; j++) redacted[o + j] = 0;
                    }
                }
                src = redacted;
                redactedOk = 1;
            }
        }
        if (isEDID && !redactedOk) {
            // Couldn't redact (alloc failed, or too short to hold a serial).
            // Never print an EDID we haven't redacted: it would leak the
            // monitor serial under a "redacted" label.
            printf("  %s = <%ld bytes, withheld (could not redact serial)>\n", label, (long)len);
        } else {
            printf("  %s = <%ld bytes%s> ", label, (long)len, redactedOk ? " serial-redacted" : "");
            for (CFIndex i = 0; i < len; i++) printf("%02x", src[i]); // full, no truncation
            printf("\n");
        }
        if (redacted) free(redacted);
    } else {
        printf("  %s = <type %lu>\n", label, (unsigned long)tid);
    }
}

static void printKey(io_service_t svc, const char *key) {
    CFTypeRef v = readKey(svc, key);
    printValue(key, v);
    if (v) CFRelease(v);
}

// Monitor identity (EDID, BranchDeviceID, names) can live top-level or inside
// the "Metadata" sub-dictionary, depending on the connection. Dump the whole
// Metadata dict so we capture it wherever it sits.
static void dumpMetadata(io_service_t svc) {
    CFTypeRef meta = readKey(svc, "Metadata");
    if (!meta) { printf("  Metadata = (absent)\n"); return; }
    if (CFGetTypeID(meta) != CFDictionaryGetTypeID()) { CFRelease(meta); return; }

    printf("  --- Metadata ---\n");
    CFIndex n = CFDictionaryGetCount(meta);
    const void **keys = malloc(n * sizeof(void *));
    const void **vals = malloc(n * sizeof(void *));
    if (keys && vals) {
        CFDictionaryGetKeysAndValues(meta, keys, vals);
        for (CFIndex i = 0; i < n; i++) {
            char kbuf[256] = {0};
            if (CFGetTypeID(keys[i]) == CFStringGetTypeID())
                CFStringGetCString(keys[i], kbuf, sizeof(kbuf), kCFStringEncodingUTF8);
            // The raw monitor serial number is identifying; the test kit
            // promises not to collect serials, so skip it. (The EDID printed
            // above is already serial-redacted.)
            if (strcasestr(kbuf, "Serial") != NULL) {
                printf("  Metadata.%s = (redacted)\n", kbuf);
                continue;
            }
            char label[300];
            snprintf(label, sizeof(label), "Metadata.%s", kbuf);
            printValue(label, vals[i]);
        }
    }
    free(keys);
    free(vals);
    CFRelease(meta);
}

int main(void) {
    printf("33_displayport_capability: IOPortTransportStateDisplayPort nodes\n");
    printf("uid=%d\n\n", getuid());

    io_iterator_t iter = 0;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOPortTransportStateDisplayPort"), &iter);
    if (kr != KERN_SUCCESS) {
        printf("(IOServiceGetMatchingServices failed: 0x%x)\n", kr);
        return 0;
    }

    // Top-level link-state keys we care about. Monitor identity comes from the
    // Metadata dump below.
    const char *keys[] = {
        "Active", "LinkRate", "LinkRateDescription", "LaneCount", "MaxLaneCount",
        "Tunneled", "HPD_State", "HPD_StateDescription", "SinkCount",
        "NominalSignalingFrequenciesHz", "DFP Type", "DFP Type Description",
        "BranchDeviceID", "TransportType", "TransportTypeDescription",
        "ParentPortType", "ParentPortTypeDescription", "ParentPortNumber",
        "EDID", "EDIDChanged",
        NULL
    };

    io_service_t svc;
    int count = 0;
    while ((svc = IOIteratorNext(iter)) != 0) {
        printf("=== DisplayPort node [%d] ===\n", count++);
        for (int i = 0; keys[i]; i++) printKey(svc, keys[i]);
        dumpMetadata(svc);
        printf("\n");
        IOObjectRelease(svc);
    }
    IOObjectRelease(iter);

    if (count == 0) printf("(no DisplayPort nodes; likely no display attached)\n");
    return 0;
}
