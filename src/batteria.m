// Batteria — controllo del limite di carica via PowerUI (MCL nativo macOS 26.4+)
// Uso: batteria [status|limits|limit <n>|enable|disable|watch]
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <objc/runtime.h>

@interface PUSCC : NSObject
@property (copy) NSString *clientName;
- (instancetype)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)enableMCL:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
- (unsigned long long)isMCLCurrentlyEnabled:(NSError **)error;
- (BOOL)temporarilyDisableMCL:(NSError **)error;
- (BOOL)temporarilyEnableCharging:(NSError **)error;
- (NSArray *)availableChargeLimitsWithError:(NSError **)error;
@end

static PUSCC *makeClient(void) {
    void *h = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW);
    if (!h) return nil;
    Class cls = objc_getClass("PowerUISmartChargeClient");
    if (!cls) return nil;
    return [[cls alloc] initWithClientName:@"Batteria"];
}

static NSDictionary *batteryProps(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!svc) return nil;
    CFMutableDictionaryRef props = NULL;
    IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0);
    IOObjectRelease(svc);
    return props ? (__bridge_transfer NSDictionary *)props : nil;
}

static int batteryPercent(void) {
    NSDictionary *b = batteryProps();
    NSNumber *cap = b[@"CurrentCapacity"], *max = b[@"MaxCapacity"];
    if (!cap || !max || max.doubleValue == 0) return -1;
    return (int)lround(cap.doubleValue * 100.0 / max.doubleValue);
}

static void printStatus(void) {
    NSDictionary *b = batteryProps();
    printf("== Batteria ==\n");
    if (b) {
        NSNumber *cap = b[@"CurrentCapacity"], *max = b[@"MaxCapacity"];
        NSNumber *ext = b[@"ExternalConnected"], *chg = b[@"IsCharging"], *full = b[@"FullyCharged"];
        NSNumber *cycles = b[@"CycleCount"];
        if (!cycles) cycles = b[@"BatteryData"][@"CycleCount"];
        NSNumber *temp = b[@"Temperature"];
        if (cap && max) printf("  Carica:        %d%%\n", (int)lround(cap.doubleValue * 100.0 / max.doubleValue));
        printf("  Alimentazione: %s\n", ext.boolValue ? "adattatore collegato" : "batteria");
        printf("  Stato:         %s\n", chg.boolValue ? "in carica" : (full.boolValue ? "carica completa" : "non in carica"));
        if (cycles) printf("  Cicli:         %d\n", cycles.intValue);
        if (temp) printf("  Temperatura:   %.1f °C\n", temp.doubleValue / 100.0);
    } else {
        printf("  (info batteria non disponibile)\n");
    }

    printf("\n== Limite di carica (MCL nativo) ==\n");
    PUSCC *c = makeClient();
    if (!c) { printf("  PowerUI non disponibile\n"); return; }
    if (![c isMCLSupported]) { printf("  MCL non supportato su questo Mac\n"); return; }
    NSError *e = nil;
    unsigned char lim = [c getMCLLimitWithError:&e];
    printf("  Limite:        %u%%\n", (unsigned)lim);
    e = nil;
    unsigned long long en = [c isMCLCurrentlyEnabled:&e];
    printf("  Attivo:        %s\n", en ? "sì" : "no");
}

static void printLimits(PUSCC *c) {
    NSError *e = nil;
    NSArray *limits = [c availableChargeLimitsWithError:&e];
    if (!limits) {
        fprintf(stderr, "Errore lettura limiti: %s\n", e.localizedDescription.UTF8String);
        return;
    }
    printf("Limiti disponibili: ");
    for (NSUInteger i = 0; i < limits.count; i++) {
        printf("%s%s", i ? ", " : "", [limits[i] stringValue].UTF8String);
    }
    printf("\n");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *cmd = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"status";

        if ([cmd isEqualToString:@"help"] || [cmd isEqualToString:@"-h"] || [cmd isEqualToString:@"--help"]) {
            printf("Uso: batteria <comando>\n\n"
                   "  status            stato batteria + limite di carica\n"
                   "  limits            limiti disponibili\n"
                   "  limit <n>         imposta il limite (es: batteria limit 80) e lo attiva\n"
                   "  enable            attiva il limite di carica\n"
                   "  disable           disattiva il limite di carica\n"
                   "  pause             sospendi temporaneamente (carica al 100%%)\n"
                   "  watch             monitoraggio continuo dello stato\n");
            return 0;
        }

        if ([cmd isEqualToString:@"watch"]) {
            while (1) {
                fflush(stdout);
                printf("\033[2J\033[H"); // clear
                printStatus();
                fflush(stdout);
                sleep(5);
            }
        }

        if ([cmd isEqualToString:@"status"]) {
            printStatus();
            return 0;
        }

        PUSCC *c = makeClient();
        if (!c) {
            fprintf(stderr, "Errore: impossibile inizializzare PowerUISmartChargeClient\n");
            return 1;
        }

        if ([cmd isEqualToString:@"limits"]) {
            printLimits(c);
            return 0;
        }

        if ([cmd isEqualToString:@"limit"] || [cmd isEqualToString:@"set"]) {
            if (argc < 3) { fprintf(stderr, "Uso: batteria limit <n>\n"); return 1; }
            int target = atoi(argv[2]);
            NSError *e = nil;
            NSArray *limits = [c availableChargeLimitsWithError:&e];
            if (limits && ![limits containsObject:@(target)]) {
                fprintf(stderr, "Errore: %d%% non è un limite valido. Disponibili: ", target);
                for (NSUInteger i = 0; i < limits.count; i++)
                    fprintf(stderr, "%s%s", i ? ", " : "", [limits[i] stringValue].UTF8String);
                fprintf(stderr, "\n");
                return 1;
            }
            e = nil;
            if (![c setMCLLimit:(unsigned char)target error:&e]) {
                fprintf(stderr, "Errore impostazione limite: %s\n", e.localizedDescription.UTF8String);
                return 1;
            }
            e = nil;
            if (![c enableMCL:&e]) {
                fprintf(stderr, "Limite impostato a %d%%, ma attivazione fallita: %s\n",
                        target, e.localizedDescription.UTF8String);
                return 1;
            }
            printf("Limite di carica impostato: %d%% (attivo)\n", target);
            return 0;
        }

        if ([cmd isEqualToString:@"enable"]) {
            NSError *e = nil;
            if (![c enableMCL:&e]) {
                fprintf(stderr, "Errore: %s\n", e.localizedDescription.UTF8String);
                return 1;
            }
            printf("Limite di carica attivato\n");
            return 0;
        }

        if ([cmd isEqualToString:@"disable"]) {
            NSError *e = nil;
            if (![c disableMCL:&e]) {
                fprintf(stderr, "Errore: %s\n", e.localizedDescription.UTF8String);
                return 1;
            }
            printf("Limite di carica disattivato\n");
            return 0;
        }

        if ([cmd isEqualToString:@"pause"]) {
            NSError *e = nil;
            if (![c temporarilyEnableCharging:&e]) {
                fprintf(stderr, "Errore: %s\n", e.localizedDescription.UTF8String);
                return 1;
            }
            printf("Carica temporaneamente abilitata (fino al 100%%)\n");
            return 0;
        }

        fprintf(stderr, "Comando sconosciuto: %s (usa 'batteria help')\n", argv[1]);
        return 1;
    }
}
