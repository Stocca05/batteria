// BatteriaApp.m — app menu bar con dashboard per il controllo batteria (PowerUI MCL)
#import <Cocoa/Cocoa.h>
#import "MCLClient.h"
#import "BatteryInfo.h"
#import "SMCTemp.h"

#define K_SAIL @"sailEnabled"
#define K_HEAT @"heatEnabled"
#define K_HEAT_THR @"heatThreshold"
#define K_USER_LIMIT @"userLimit"

static MCLClient *gClient;
static NSStatusItem *gItem;
static NSPopover *gPopover;

static MCLClient *Client(void) {
    if (!gClient) gClient = MCLMakeClient(@"Batteria");
    return gClient;
}

static NSString *ErrStr(NSError *e) {
    return e.localizedDescription ?: e.description ?: @"errore sconosciuto";
}

#pragma mark - Header batteria disegnato

@interface BatteryHeaderView : NSView
@property (nonatomic) int percent;
@property (nonatomic) BOOL charging;
@property (nonatomic, copy) NSString *stateText;
@end

@implementation BatteryHeaderView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    CGFloat h = 56;
    NSRect shell = NSMakeRect(4, 6, b.size.width - 24, h);
    NSRect cap = NSMakeRect(NSMaxX(shell) + 2, NSMidY(shell) - 7, 6, 14);
    [[NSColor quaternaryLabelColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:cap xRadius:2 yRadius:2] fill];
    [[NSColor quaternaryLabelColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:shell xRadius:10 yRadius:10] fill];

    CGFloat pct = MAX(0, MIN(100, self.percent)) / 100.0;
    NSRect inner = NSInsetRect(shell, 3, 3);
    NSRect fill = inner;
    fill.size.width = MAX(6, inner.size.width * pct);
    NSColor *color = self.charging ? [NSColor systemGreenColor]
        : (self.percent <= 20 ? [NSColor systemRedColor]
        : (self.percent <= 40 ? [NSColor systemOrangeColor] : [NSColor systemGreenColor]));
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:7 yRadius:7] fill];

    NSString *pctStr = self.percent >= 0 ? [NSString stringWithFormat:@"%d%%", self.percent] : @"--%";
    NSDictionary *attrs = @{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:24 weight:NSFontWeightBold],
                             NSForegroundColorAttributeName: [NSColor labelColor] };
    NSSize sz = [pctStr sizeWithAttributes:attrs];
    [pctStr drawAtPoint:NSMakePoint(NSMidX(shell) - sz.width / 2, NSMidY(shell) - sz.height / 2) withAttributes:attrs];

    NSDictionary *small = @{ NSFontAttributeName: [NSFont systemFontOfSize:11],
                             NSForegroundColorAttributeName: [NSColor secondaryLabelColor] };
    NSSize ssz = [self.stateText sizeWithAttributes:small];
    [self.stateText drawAtPoint:NSMakePoint(NSMidX(b) - ssz.width / 2, NSMaxY(shell) + 2) withAttributes:small];
}
@end

#pragma mark - Dashboard

@interface DashboardViewController : NSViewController
- (void)refreshUI;
@end

@implementation DashboardViewController {
    BatteryHeaderView *_header;
    NSTextField *_lCycles, *_lHealth, *_lCap, *_lTemp, *_lTime, *_lWatts;
    NSSlider *_slider;
    NSTextField *_limitValue;
    NSButton *_mclCheck, *_sailCheck, *_heatCheck, *_obcCheck, *_loginCheck;
    NSPopUpButton *_heatPop;
    NSTextField *_note;
}

static NSTextField *Label(NSString *s, CGFloat size, BOOL bold) {
    NSTextField *t = [NSTextField labelWithString:s];
    t.font = bold ? [NSFont systemFontOfSize:size weight:NSFontWeightSemibold] : [NSFont systemFontOfSize:size];
    return t;
}

static NSTextField *ValueLabel(void) {
    NSTextField *t = [NSTextField labelWithString:@"-"];
    t.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    t.textColor = [NSColor secondaryLabelColor];
    return t;
}

static NSBox *Separator(void) {
    NSBox *b = [[NSBox alloc] init];
    b.boxType = NSBoxSeparator;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    return b;
}

static NSButton *LockedButton(NSString *title) {
    NSButton *b = [NSButton buttonWithTitle:title target:nil action:nil];
    b.bezelStyle = NSBezelStyleRounded;
    b.controlSize = NSControlSizeSmall;
    b.enabled = NO;
    b.toolTip = @"Richiede un helper privilegiato (root): non disponibile in questa build.";
    return b;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 680)];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 7;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:root.bottomAnchor constant:-10],
    ]];

    void (^addFull)(NSView *) = ^(NSView *v) {
        [stack addArrangedSubview:v];
        [v.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    };

    _header = [[BatteryHeaderView alloc] initWithFrame:NSMakeRect(0, 0, 292, 82)];
    _header.stateText = @"";
    [stack addArrangedSubview:_header];
    [_header.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [_header.heightAnchor constraintEqualToConstant:82].active = YES;

    _lCycles = ValueLabel(); _lHealth = ValueLabel(); _lCap = ValueLabel();
    _lTemp = ValueLabel(); _lTime = ValueLabel(); _lWatts = ValueLabel();
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[Label(@"Cicli", 12, NO), _lCycles],
        @[Label(@"Salute", 12, NO), _lHealth],
        @[Label(@"Capacità", 12, NO), _lCap],
        @[Label(@"Temperatura", 12, NO), _lTemp],
        @[Label(@"Tempo rimanente", 12, NO), _lTime],
        @[Label(@"Potenza", 12, NO), _lWatts],
    ]];
    grid.rowSpacing = 3;
    grid.columnSpacing = 10;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:0].width = 110;
    [grid columnAtIndex:1].width = 170;
    [stack addArrangedSubview:grid];

    addFull(Separator());

    NSStackView *limRow = [[NSStackView alloc] init];
    limRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    [limRow addArrangedSubview:Label(@"Limite di carica", 13, YES)];
    [limRow addArrangedSubview:[NSView new]];
    _limitValue = ValueLabel();
    _limitValue.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold];
    _limitValue.textColor = [NSColor labelColor];
    [limRow addArrangedSubview:_limitValue];
    addFull(limRow);

    _slider = [NSSlider sliderWithValue:80 minValue:80 maxValue:100 target:self action:@selector(sliderMoved:)];
    _slider.numberOfTickMarks = 5;
    _slider.allowsTickMarkValuesOnly = NO;
    _slider.continuous = YES;
    addFull(_slider);

    _mclCheck = [NSButton checkboxWithTitle:@"Mantieni limite attivo" target:self action:@selector(toggleMCL:)];
    [stack addArrangedSubview:_mclCheck];

    NSButton *topUp = [NSButton buttonWithTitle:@"Carica al 100% (una volta)" target:self action:@selector(topUp:)];
    topUp.bezelStyle = NSBezelStyleRounded;
    topUp.controlSize = NSControlSizeSmall;
    [stack addArrangedSubview:topUp];

    addFull(Separator());

    _sailCheck = [NSButton checkboxWithTitle:@"Sailing Mode (oscilla limite-5 ↔ limite)" target:self action:@selector(toggleSail:)];
    [stack addArrangedSubview:_sailCheck];

    NSStackView *heatRow = [[NSStackView alloc] init];
    heatRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _heatCheck = [NSButton checkboxWithTitle:@"Protezione calore oltre" target:self action:@selector(toggleHeat:)];
    [heatRow addArrangedSubview:_heatCheck];
    _heatPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 70, 0) pullsDown:NO];
    [_heatPop addItemsWithTitles:@[@"38 °C", @"40 °C", @"42 °C", @"45 °C"]];
    [_heatPop setTarget:self];
    [_heatPop setAction:@selector(heatThresholdChanged:)];
    [heatRow addArrangedSubview:_heatPop];
    [stack addArrangedSubview:heatRow];

    _obcCheck = [NSButton checkboxWithTitle:@"Caricamento ottimizzato Apple" target:self action:@selector(toggleOBC:)];
    [stack addArrangedSubview:_obcCheck];

    _loginCheck = [NSButton checkboxWithTitle:@"Avvia al login" target:self action:@selector(toggleLogin:)];
    [stack addArrangedSubview:_loginCheck];

    addFull(Separator());

    [stack addArrangedSubview:Label(@"Funzioni bloccate (richiedono helper root):", 11, NO)];
    NSGridView *locked = [NSGridView gridViewWithViews:@[
        @[LockedButton(@"Limite sotto 80%"), LockedButton(@"Calibrazione")],
        @[LockedButton(@"Discharge"), LockedButton(@"Sleep a coperchio chiuso")],
    ]];
    locked.rowSpacing = 5;
    locked.columnSpacing = 8;
    [stack addArrangedSubview:locked];

    _note = Label(@"", 10, NO);
    _note.textColor = [NSColor tertiaryLabelColor];
    _note.lineBreakMode = NSLineBreakByWordWrapping;
    _note.maximumNumberOfLines = 3;
    addFull(_note);

    NSStackView *footer = [[NSStackView alloc] init];
    footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    NSButton *refresh = [NSButton buttonWithTitle:@"Aggiorna" target:self action:@selector(refreshUI)];
    refresh.bezelStyle = NSBezelStyleRounded; refresh.controlSize = NSControlSizeSmall;
    NSButton *quit = [NSButton buttonWithTitle:@"Esci" target:NSApp action:@selector(terminate:)];
    quit.bezelStyle = NSBezelStyleRounded; quit.controlSize = NSControlSizeSmall;
    NSTextField *ver = Label(@"Batteria 0.2", 10, NO);
    ver.textColor = [NSColor tertiaryLabelColor];
    [footer addArrangedSubview:refresh];
    [footer addArrangedSubview:quit];
    [footer addArrangedSubview:[NSView new]];
    [footer addArrangedSubview:ver];
    addFull(footer);

    self.view = root;
}

- (void)viewWillAppear {
    [super viewWillAppear];
    [self refreshUI];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _heatPop.enabled = YES;
}

- (void)refreshUI {
    int pct = BatteryPercentNow();
    BOOL charging = BatteryIsCharging();
    _header.percent = pct;
    _header.charging = charging;
    NSString *state = charging ? @"in carica" : (BatteryFullyCharged() ? @"carica completa"
        : (BatteryExternalConnected() ? @"carica in attesa" : @"scarica"));
    _header.stateText = [NSString stringWithFormat:@"%@ · %@", state, BatteryTimeStr()];
    [_header setNeedsDisplay:YES];

    _lCycles.stringValue = [NSString stringWithFormat:@"%d", BatteryCycleCount()];
    int health = BatteryHealthPercent();
    _lHealth.stringValue = health > 0 ? [NSString stringWithFormat:@"%d%%", health] : @"-";
    _lCap.stringValue = BatteryCapacityStr();
    double t = SMCTemperature();
    _lTemp.stringValue = isnan(t) ? @"-" : [NSString stringWithFormat:@"%.1f °C", t];
    _lTime.stringValue = BatteryTimeStr();
    _lWatts.stringValue = [NSString stringWithFormat:@"%.1f W", BatteryWatts()];

    NSError *e = nil;
    unsigned char lim = [Client() getMCLLimitWithError:&e];
    e = nil;
    BOOL mclOn = [Client() isMCLCurrentlyEnabled:&e] != 0;
    _slider.doubleValue = lim;
    _limitValue.stringValue = [NSString stringWithFormat:@"%u%%%@", (unsigned)lim, mclOn ? @"" : @" (off)"];
    _mclCheck.state = mclOn ? NSControlStateValueOn : NSControlStateValueOff;

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    _sailCheck.state = [d boolForKey:K_SAIL] ? NSControlStateValueOn : NSControlStateValueOff;
    if (lim < 85)
        _sailCheck.toolTip = @"Sailing richiede un limite ≥ 85% (MCL non scende sotto 80%).";
    else
        _sailCheck.toolTip = @"Mantiene la batteria oscillando tra limite-5% e il limite mentre è collegata.";

    _heatCheck.state = [d boolForKey:K_HEAT] ? NSControlStateValueOn : NSControlStateValueOff;
    int thr = (int)[d integerForKey:K_HEAT_THR];
    [_heatPop selectItemAtIndex:(thr == 38 ? 0 : thr == 42 ? 2 : thr == 45 ? 3 : 1)];

    e = nil;
    BOOL obc = [Client() isSmartChargingCurrentlyEnabled:&e] != 0;
    _obcCheck.state = obc ? NSControlStateValueOn : NSControlStateValueOff;

    _loginCheck.state = [NSFileManager.defaultManager fileExistsAtPath:[DashboardViewController launchAgentPath]]
        ? NSControlStateValueOn : NSControlStateValueOff;

    NSMutableString *note = [NSMutableString string];
    NSArray *ald = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apphousekitchen.aldente-pro"];
    if (ald.count > 0) [note appendString:@"AlDente è attivo: può ripristinare il suo limite. "];
    if (pct >= 0 && pct < 80 && charging && [d boolForKey:K_HEAT] && !isnan(t) && t >= thr)
        [note appendString:@"Batteria calda sotto l'80%: la carica non può essere interrotta via MCL. "];
    _note.stringValue = note;
}

- (void)showError:(NSString *)msg {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Batteria";
    a.informativeText = msg;
    [a runModal];
}

- (void)applyLimit:(int)target {
    NSError *e = nil;
    if (![Client() setMCLLimit:(unsigned char)target error:&e]) {
        [self showError:[NSString stringWithFormat:@"Impossibile impostare il limite: %@", ErrStr(e)]];
        return;
    }
    if (target < 100) {
        e = nil;
        if (![Client() enableMCL:&e])
            [self showError:[NSString stringWithFormat:@"Limite impostato ma attivazione fallita: %@", ErrStr(e)]];
    }
    [NSUserDefaults.standardUserDefaults setInteger:target forKey:K_USER_LIMIT];
    [self refreshUI];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshUI];
    });
}

- (void)sliderMoved:(NSSlider *)s {
    _limitValue.stringValue = [NSString stringWithFormat:@"%d%%", (int)s.doubleValue];
    if (NSApp.currentEvent.type == NSEventTypeLeftMouseUp)
        [self applyLimit:(int)s.doubleValue];
}

- (void)toggleMCL:(NSButton *)b {
    NSError *e = nil;
    BOOL on = [Client() isMCLCurrentlyEnabled:&e] != 0;
    e = nil;
    if (on) {
        if (![Client() disableMCL:&e]) { [self showError:ErrStr(e)]; return; }
    } else {
        if (![Client() enableMCL:&e]) { [self showError:ErrStr(e)]; return; }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshUI];
    });
}

- (void)topUp:(id)sender {
    NSError *e = nil;
    if (![Client() temporarilyEnableCharging:&e]) { [self showError:ErrStr(e)]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshUI];
    });
}

- (void)toggleSail:(NSButton *)b {
    [NSUserDefaults.standardUserDefaults setBool:b.state == NSControlStateValueOn forKey:K_SAIL];
}

- (void)toggleHeat:(NSButton *)b {
    [NSUserDefaults.standardUserDefaults setBool:b.state == NSControlStateValueOn forKey:K_HEAT];
}

- (void)heatThresholdChanged:(NSPopUpButton *)p {
    NSArray *vals = @[@38, @40, @42, @45];
    [NSUserDefaults.standardUserDefaults setInteger:[vals[p.indexOfSelectedItem] intValue] forKey:K_HEAT_THR];
}

- (void)toggleOBC:(NSButton *)b {
    NSError *e = nil;
    if (b.state == NSControlStateValueOn) {
        if (![Client() enableSmartCharging:&e]) [self showError:ErrStr(e)];
    } else {
        if (![Client() disableSmartCharging:&e]) [self showError:ErrStr(e)];
    }
}

+ (NSString *)launchAgentPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/local.batteria.plist"];
}

- (void)toggleLogin:(NSButton *)b {
    NSString *path = [DashboardViewController launchAgentPath];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (b.state == NSControlStateValueOn) {
        [fm createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *plist = @{
            @"Label": @"local.batteria",
            @"ProgramArguments": @[NSBundle.mainBundle.executablePath],
            @"RunAtLoad": @YES,
        };
        [plist writeToFile:path atomically:YES];
    } else {
        [fm removeItemAtPath:path error:nil];
        NSTask *t = [[NSTask alloc] init];
        t.launchPath = @"/bin/launchctl";
        t.arguments = @[@"bootout", [NSString stringWithFormat:@"gui/%d", getuid()], @"local.batteria"];
        t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
        t.standardError = [NSFileHandle fileHandleWithNullDevice];
        @try { [t launch]; [t waitUntilExit]; } @catch (NSException *e) {}
    }
}

@end

#pragma mark - App

@interface AppDelegate : NSObject <NSApplicationDelegate>
- (void)togglePopover:(id)sender;
@end

@implementation AppDelegate {
    DashboardViewController *_dash;
    NSTimer *_uiTimer;
    NSTimer *_engineTimer;
    BOOL _sailDown;
    int _sailUpLimit;
    BOOL _heatActive;
    int _heatSavedLimit;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    Client();
    gItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    gItem.button.title = @"--%";
    gItem.button.target = self;
    gItem.button.action = @selector(togglePopover:);
    [gItem.button sendActionOn:NSEventMaskLeftMouseUp];

    _dash = [[DashboardViewController alloc] init];
    gPopover = [[NSPopover alloc] init];
    gPopover.contentViewController = _dash;
    gPopover.behavior = NSPopoverBehaviorTransient;
    gPopover.contentSize = NSMakeSize(320, 680);

    [self updateTitle];
    _uiTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(uiTick) userInfo:nil repeats:YES];
    _engineTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(engineTick) userInfo:nil repeats:YES];
}

- (void)togglePopover:(id)sender {
    if (gPopover.isShown) {
        [gPopover performClose:nil];
    } else {
        [_dash refreshUI];
        [gPopover showRelativeToRect:gItem.button.bounds ofView:gItem.button preferredEdge:NSRectEdgeMinY];
    }
}

- (void)updateTitle {
    int pct = BatteryPercentNow();
    BOOL charging = BatteryIsCharging();
    gItem.button.title = pct >= 0 ? [NSString stringWithFormat:@"%d%%%s", pct, charging ? "+" : ""] : @"--%";
    gItem.button.toolTip = @"Batteria — clic per la dashboard";
}

- (void)uiTick {
    [self updateTitle];
    if (gPopover.isShown) [_dash refreshUI];
}

- (void)engineTick {
    NSError *e = nil;
    unsigned char lim = [Client() getMCLLimitWithError:&e];
    e = nil;
    BOOL mclOn = [Client() isMCLCurrentlyEnabled:&e] != 0;
    int soc = BatteryPercentNow();
    BOOL ext = BatteryExternalConnected();
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;

    // Sailing: oscillazione limite-5 <-> limite (solo limite >= 85%)
    if ([d boolForKey:K_SAIL] && mclOn && ext && soc >= 0) {
        if (_sailDown) {
            if (soc <= _sailUpLimit - 5) {
                e = nil;
                if ([Client() setMCLLimit:(unsigned char)_sailUpLimit error:&e]) _sailDown = NO;
            }
        } else if (lim >= 85 && soc >= lim && !BatteryIsCharging()) {
            _sailUpLimit = lim;
            e = nil;
            if ([Client() setMCLLimit:(unsigned char)(lim - 5) error:&e]) _sailDown = YES;
        }
    } else if (_sailDown) {
        int ul = (int)[d integerForKey:K_USER_LIMIT];
        if (ul < 80) ul = 80;
        if (lim != ul) { e = nil; [Client() setMCLLimit:(unsigned char)ul error:&e]; }
        _sailDown = NO;
    }

    // Heat protection (best effort): se in carica e calda, abbassa il limite al gradino sotto la carica
    double t = SMCTemperature();
    if ([d boolForKey:K_HEAT] && !isnan(t)) {
        int thr = (int)[d integerForKey:K_HEAT_THR];
        if (!_heatActive && BatteryIsCharging() && t >= thr) {
            _heatActive = YES;
            _heatSavedLimit = lim;
            int tgt = (soc / 5) * 5;
            if (tgt > lim) tgt = lim;
            if (tgt < 80) tgt = 80;
            if (tgt < lim) { e = nil; [Client() setMCLLimit:(unsigned char)tgt error:&e]; }
        } else if (_heatActive && (t <= thr - 2 || !BatteryIsCharging())) {
            _heatActive = NO;
            if (lim != _heatSavedLimit) { e = nil; [Client() setMCLLimit:(unsigned char)_heatSavedLimit error:&e]; }
        }
    }
}

@end

static void Dump(void) {
    int pct = BatteryPercentNow();
    NSError *e = nil;
    unsigned char lim = [Client() getMCLLimitWithError:&e];
    e = nil;
    unsigned long long en = [Client() isMCLCurrentlyEnabled:&e];
    e = nil;
    unsigned long long obc = [Client() isSmartChargingCurrentlyEnabled:&e];
    double t = SMCTemperature();
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    printf("Batteria: %d%% (%s)\n", pct, BatteryIsCharging() ? "in carica" : BatteryExternalConnected() ? "attesa" : "scarica");
    printf("Cicli: %d  Salute: %d%%  Temp: %.1f C  Potenza: %.1f W\n", BatteryCycleCount(), BatteryHealthPercent(), t, BatteryWatts());
    printf("MCL: limite=%u attivo=%llu\n", (unsigned)lim, en);
    printf("OBC (caricamento ottimizzato): %llu\n", obc);
    printf("Sailing: %s  Heat: %s (soglia %d C)\n",
           [d boolForKey:K_SAIL] ? "on" : "off",
           [d boolForKey:K_HEAT] ? "on" : "off",
           (int)[d integerForKey:K_HEAT_THR]);
    id st = [Client() status];
    printf("PowerUI status: %s\n", [st isKindOfClass:[NSDictionary class]] ? [[(NSDictionary *)st objectForKey:@"Enabled"] description].UTF8String : "?");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults registerDefaults:@{
            K_SAIL: @NO,
            K_HEAT: @NO,
            K_HEAT_THR: @40,
            K_USER_LIMIT: @80,
        }];
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (argc > 1 && strcmp(argv[1], "--dump") == 0) {
            Dump();
            return 0;
        }
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        if (argc > 1 && strcmp(argv[1], "--uitest") == 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [delegate togglePopover:nil];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [gPopover performClose:nil];
                printf("uitest ok\n");
                exit(0);
            });
        }
        [app run];
    }
    return 0;
}
