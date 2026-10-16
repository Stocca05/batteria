// SMCTemp.h — lettura read-only della temperatura batteria (TB0T) via AppleSMC
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersionT;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitDataT;
typedef struct { uint32_t dataSize, dataType, dataAttributes; } SMCKeyInfoDataT;
typedef struct {
    uint32_t key;
    SMCVersionT vers;
    SMCPLimitDataT pLimit;
    SMCKeyInfoDataT keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyDataT;

static inline uint32_t smcStr2Key(const char *s) {
    return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) | ((uint32_t)s[2] << 8) | (uint32_t)s[3];
}

static inline double SMCTemperature(void) {
    static io_connect_t conn = 0;
    static int failed = 0;
    if (failed) return NAN;
    if (!conn) {
        io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
        if (!svc) svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"));
        if (!svc || IOServiceOpen(svc, mach_task_self(), 0, &conn)) { failed = 1; return NAN; }
    }
    SMCKeyDataT in, out;
    memset(&in, 0, sizeof(in)); memset(&out, 0, sizeof(out));
    in.key = smcStr2Key("TB0T");
    in.data8 = 9;
    size_t outSz = sizeof(SMCKeyDataT);
    if (IOConnectCallStructMethod(conn, 2, &in, sizeof(in), &out, &outSz)) return NAN;
    uint32_t size = out.keyInfo.dataSize;
    uint32_t type = out.keyInfo.dataType;
    memset(&in, 0, sizeof(in));
    in.key = smcStr2Key("TB0T");
    in.keyInfo.dataSize = size;
    in.data8 = 5;
    memset(&out, 0, sizeof(out));
    if (IOConnectCallStructMethod(conn, 2, &in, sizeof(in), &out, &outSz)) return NAN;
    char t[5] = { (char)(type >> 24), (char)(type >> 16), (char)(type >> 8), (char)type, 0 };
    for (int i = 3; i >= 0 && t[i] == ' '; i--) t[i] = 0;
    if (strcmp(t, "flt") == 0 && size == 4) {
        float f;
        memcpy(&f, out.bytes, 4);
        return f;
    }
    if (strcmp(t, "sp78") == 0 && size == 2) {
        int16_t v = (int16_t)((out.bytes[0] << 8) | out.bytes[1]);
        return v / 256.0;
    }
    return NAN;
}
