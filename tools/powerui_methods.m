#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

int main(void) {
    @autoreleasepool {
        void *h = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW);
        if (!h) { printf("dlopen failed\n"); return 1; }

        unsigned int n = 0;
        const char **names = objc_copyClassNamesForImage("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", &n);
        if (names) {
            printf("== classi PowerUI rilevanti ==\n");
            for (unsigned i = 0; i < n; i++) {
                const char *c = names[i];
                if (strstr(c, "Charge") || strstr(c, "MCL") || strstr(c, "Battery") || strstr(c, "Discharge") || strstr(c, "PowerUI"))
                    printf("  %s\n", c);
            }
            free(names);
        }

        Class cls = objc_getClass("PowerUISmartChargeClient");
        if (!cls) { printf("classe non trovata\n"); return 1; }
        printf("\n== metodi PowerUISmartChargeClient ==\n");
        unsigned mc = 0;
        Method *ms = class_copyMethodList(cls, &mc);
        for (unsigned i = 0; i < mc; i++) {
            printf("  -[%s]  %s\n", sel_getName(method_getName(ms[i])), method_getTypeEncoding(ms[i]));
        }
        free(ms);
        Method *cms = class_copyMethodList(object_getClass(cls), NULL);
        if (cms) {
            printf("\n== metodi di classe ==\n");
            unsigned c; cms = class_copyMethodList(object_getClass(cls), &c);
            for (unsigned i = 0; i < c; i++) printf("  +[%s]  %s\n", sel_getName(method_getName(cms[i])), method_getTypeEncoding(cms[i]));
            free(cms);
        }

        id client = ((id (*)(id, SEL, NSString *))objc_msgSend)([cls alloc], sel_registerName("initWithClientName:"), @"BatteriaProbe");
        if (!client) { printf("alloc client fallito\n"); return 1; }

        printf("\n== test setMCLLimit:75 ==\n");
        NSError *e = nil;
        unsigned char cur = ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(client, sel_registerName("getMCLLimitWithError:"), &e);
        printf("prima:      %u (err: %s)\n", cur, e.localizedDescription.UTF8String ?: "-");
        e = nil;
        BOOL ok = ((BOOL (*)(id, SEL, unsigned char, NSError **))objc_msgSend)(client, sel_registerName("setMCLLimit:error:"), 75, &e);
        printf("set 75:     %s (err: %s)\n", ok ? "OK" : "FALLITO", e.localizedDescription.UTF8String ?: e.description.UTF8String ?: "-");
        e = nil;
        unsigned char now = ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(client, sel_registerName("getMCLLimitWithError:"), &e);
        printf("dopo:       %u\n", now);
        e = nil;
        ((BOOL (*)(id, SEL, unsigned char, NSError **))objc_msgSend)(client, sel_registerName("setMCLLimit:error:"), cur, &e);
        e = nil;
        printf("ripristino: %u\n", ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(client, sel_registerName("getMCLLimitWithError:"), &e));
    }
    return 0;
}
