#include <stdio.h>
#include <string.h>
#include <IOKit/IOKitLib.h>
#include <stdint.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize, dataType, dataAttributes; } SMCKeyInfoData;
typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimit;
    SMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData_t;

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_KEYINFO 9

static io_connect_t conn = 0;

static uint32_t str2key(const char *s) {
    return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) | ((uint32_t)s[2] << 8) | (uint32_t)s[3];
}

static int smcCall(int index, SMCKeyData_t *in, SMCKeyData_t *out) {
    size_t outSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, index, in, sizeof(SMCKeyData_t), out, &outSize);
}

static void readKey(const char *key) {
    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in)); memset(&out, 0, sizeof(out));
    in.key = str2key(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (smcCall(KERNEL_INDEX_SMC, &in, &out)) { printf("%.4s: CALL-ERR\n", key); return; }
    uint32_t size = out.keyInfo.dataSize;
    uint32_t type = out.keyInfo.dataType;
    memset(&in, 0, sizeof(in));
    in.key = str2key(key);
    in.keyInfo.dataSize = size;
    in.data8 = SMC_CMD_READ_BYTES;
    SMCKeyData_t out2;
    memset(&out2, 0, sizeof(out2));
    if (smcCall(KERNEL_INDEX_SMC, &in, &out2)) { printf("%.4s: READ-ERR\n", key); return; }
    char t[5] = { (char)(type>>24), (char)(type>>16), (char)(type>>8), (char)type, 0 };
    printf("%.4s  type=%.4s size=%u  hex=", key, t, size);
    for (uint32_t i = 0; i < size && i < 16; i++) printf("%02x ", out2.bytes[i]);
    if (size == 1) printf("  u8=%u", out2.bytes[0]);
    else if (size == 2) printf("  u16=%u", (out2.bytes[1]<<8)|out2.bytes[0]);
    else if (size == 4) { uint32_t v = out2.bytes[0]|(out2.bytes[1]<<8)|(out2.bytes[2]<<16)|((uint32_t)out2.bytes[3]<<24); printf("  u32=%u", v); }
    printf("\n");
}

int main(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"));
    if (!svc) { printf("no AppleSMC service\n"); return 1; }
    if (IOServiceOpen(svc, mach_task_self(), 0, &conn)) { printf("open failed\n"); return 1; }
    const char *keys[] = {"CH0B","CH0C","CH0I","CHIE","CHTE","BCLM","BFCL","BRSC","ACEN","CHWA","CHSC","PSTR","AC-W","TB0T","B0AV","B0AC"};
    for (unsigned i = 0; i < sizeof(keys)/sizeof(keys[0]); i++) readKey(keys[i]);
    IOServiceClose(conn);
    return 0;
}
