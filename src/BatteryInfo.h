// BatteryInfo.h — lettura stato batteria (IOKit AppleSmartBattery + IOPowerSources)
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

static inline NSDictionary *BatteryProps(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!svc) return nil;
    CFMutableDictionaryRef props = NULL;
    IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0);
    IOObjectRelease(svc);
    return props ? (__bridge_transfer NSDictionary *)props : nil;
}

static inline NSDictionary *PowerSourceDesc(void) {
    CFTypeRef blob = IOPSCopyPowerSourcesInfo();
    if (!blob) return nil;
    CFArrayRef list = IOPSCopyPowerSourcesList(blob);
    NSDictionary *desc = nil;
    if (list && CFArrayGetCount(list) > 0)
        desc = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(list, 0));
    if (list) CFRelease(list);
    CFRelease(blob);
    return desc;
}

static inline int BatteryPercentNow(void) {
    NSDictionary *b = BatteryProps();
    NSNumber *cap = b[@"CurrentCapacity"], *max = b[@"MaxCapacity"];
    if (!cap || !max || max.doubleValue == 0) return -1;
    return (int)lround(cap.doubleValue * 100.0 / max.doubleValue);
}

static inline BOOL BatteryIsCharging(void) {
    return [BatteryProps()[@"IsCharging"] boolValue];
}

static inline BOOL BatteryExternalConnected(void) {
    return [BatteryProps()[@"ExternalConnected"] boolValue];
}

static inline BOOL BatteryFullyCharged(void) {
    return [BatteryProps()[@"FullyCharged"] boolValue];
}

static inline int BatteryCycleCount(void) {
    return [BatteryProps()[@"CycleCount"] intValue];
}

static inline int BatteryHealthPercent(void) {
    NSDictionary *b = BatteryProps();
    double design = [b[@"DesignCapacity"] doubleValue];
    double raw = [b[@"AppleRawMaxCapacity"] doubleValue] ?: [b[@"NominalChargeCapacity"] doubleValue];
    if (design <= 0 || raw <= 0) return -1;
    return (int)lround(raw * 100.0 / design);
}

static inline NSString *BatteryCapacityStr(void) {
    NSDictionary *b = BatteryProps();
    NSNumber *raw = b[@"AppleRawCurrentCapacity"], *max = b[@"AppleRawMaxCapacity"];
    if (!raw || !max) return @"-";
    return [NSString stringWithFormat:@"%@ / %@ mAh", raw, max];
}

// minuti; -1 se in calcolo
static inline int BatteryTimeRemainingMin(void) {
    NSDictionary *d = PowerSourceDesc();
    if (!d) return -1;
    if ([d[@kIOPSIsChargingKey] boolValue])
        return [d[@kIOPSTimeToFullChargeKey] intValue];
    return [d[@kIOPSTimeToEmptyKey] intValue];
}

static inline NSString *BatteryTimeStr(void) {
    int m = BatteryTimeRemainingMin();
    if (m <= 0) return @"in calcolo";
    if (m >= 60) return [NSString stringWithFormat:@"%dh %02dm", m / 60, m % 60];
    return [NSString stringWithFormat:@"%dm", m];
}

// watt istantanei (positivo = assorbimento dalla rete quando in carica)
static inline double BatteryWatts(void) {
    NSDictionary *b = BatteryProps();
    double mA = [b[@"Amperage"] doubleValue];
    double mV = [b[@"Voltage"] doubleValue];
    return fabs(mA * mV) / 1e6;
}
