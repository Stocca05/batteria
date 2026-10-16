// MCLClient.h — facade per PowerUISmartChargeClient (framework privato PowerUI).
// L'interfaccia descrive la classe privata; gli oggetti si creano con MCLMakeClient().
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>

@interface MCLClient : NSObject
- (instancetype)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)enableMCL:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
- (unsigned long long)isMCLCurrentlyEnabled:(NSError **)error;
- (BOOL)temporarilyDisableMCL:(NSError **)error;
- (BOOL)temporarilyEnableCharging:(NSError **)error;
- (BOOL)temporarilyOverrideMCLTargetSoC:(unsigned char)soc error:(NSError **)error;
- (NSArray *)availableChargeLimitsWithError:(NSError **)error;
- (BOOL)enableSmartCharging:(NSError **)error;
- (BOOL)disableSmartCharging:(NSError **)error;
- (unsigned long long)isSmartChargingCurrentlyEnabled:(NSError **)error;
- (id)status;
@end

static inline MCLClient *MCLMakeClient(NSString *name) {
    static void *h;
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW);
    if (!h) return nil;
    Class cls = objc_getClass("PowerUISmartChargeClient");
    if (!cls) return nil;
    return (MCLClient *)[[cls alloc] initWithClientName:name];
}
