#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

namespace Off {
    constexpr uintptr_t kFPSCamera_PlayerController = 0x130;
    constexpr uintptr_t kPlayer_NetworkController  = 0x110;
    constexpr uintptr_t kNetwork_PlayerList        = 0x78;
    constexpr uintptr_t kPlayerSnapshot_Move       = 0x18;
    constexpr uintptr_t kMovement_Position         = 0x14;

    constexpr int kScreenW = 2340;
    constexpr int kScreenH = 1080;
}

struct Vec3 { float x, y, z; };
struct Vec2 { float x, y; };

static uintptr_t g_base = 0;
static bool g_esp_enabled = false; // По умолчанию выключено
static bool g_menu_visible = false;

static uintptr_t module_base(const char* name) {
    FILE* fp = fopen("/proc/self/maps", "r"); if (!fp) return 0;
    char line[512]; uintptr_t b = 0;
    while (fgets(line, sizeof(line), fp))
        if (strstr(line, name)) { b = strtoull(line, nullptr, 16); break; }
    fclose(fp); return b;
}

template<typename T> static T rd(uintptr_t a, T fb = T{}) {
    if (a < 0x10000) return fb;
    T v; memcpy(&v, (void*)a, sizeof(T)); return v;
}

@interface ESPOverlayView : UIView
@property (nonatomic, strong) CADisplayLink* link;
@property (nonatomic, strong) UIView* menuView;
@end

@implementation ESPOverlayView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES; // Включаем, чтобы ловить тапы
    
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    // Настройка распознавателя жестов (3 пальца, 3 тапа)
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTripleTap:)];
    tapGesture.numberOfTouchesRequired = 3;
    tapGesture.numberOfTapsRequired = 3;
    tapGesture.cancelsTouchesInView = NO; // Пропускаем тапы в игру
    [self addGestureRecognizer:tapGesture];

    // Создаем меню (изначально скрыто)
    [self setupMenu];
    
    return self;
}

- (void)setupMenu {
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(50, 200, 250, 150)];
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
    self.menuView.layer.cornerRadius = 10;
    self.menuView.hidden = YES;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 250, 30)];
    title.text = @"GORILLA MENU";
    title.textColor = [UIColor greenColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [self.menuView addSubview:title];
    
    UIButton *espBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    espBtn.frame = CGRectMake(25, 60, 200, 40);
    [espBtn setTitle:@"Включить ESP" forState:UIControlStateNormal];
    [espBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    espBtn.backgroundColor = [UIColor darkGrayColor];
    espBtn.layer.cornerRadius = 5;
    [espBtn addTarget:self action:@selector(toggleESP:) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:espBtn];
    
    [self addSubview:self.menuView];
}

- (void)handleTripleTap:(UITapGestureRecognizer *)gesture {
    g_menu_visible = !g_menu_visible;
    self.menuView.hidden = !g_menu_visible;
}

- (void)toggleESP:(UIButton *)sender {
    g_esp_enabled = !g_esp_enabled;
    [sender setTitle:g_esp_enabled ? @"Выключить ESP" : @"Включить ESP" forState:UIControlStateNormal];
    sender.backgroundColor = g_esp_enabled ? [UIColor greenColor] : [UIColor darkGrayColor];
}

- (void)tick { [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    if (!g_esp_enabled) return; // Если выключено, ничего не рисуем

    if (!g_base) {
        g_base = module_base("UnityFramework");
        if (!g_base) return;
    }
    
    uintptr_t betm_func = g_base + 0x27629BC; 
    typedef void* (*GetCameraFunc)(void);
    GetCameraFunc get_camera = (GetCameraFunc)betm_func;
    uintptr_t cam = (uintptr_t)get_camera();

    if (!cam) return;
    uintptr_t localPlayer = rd<uintptr_t>(cam + Off::kFPSCamera_PlayerController);
    if (!localPlayer) return;
    uintptr_t netCtrl = rd<uintptr_t>(localPlayer + Off::kPlayer_NetworkController);
    if (!netCtrl) return;
    uintptr_t list = rd<uintptr_t>(netCtrl + Off::kNetwork_PlayerList);
    if (!list) return;
    
    int count = rd<int>(list + 0x18);
    if (count <= 0 || count > 64) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 2.0);

    for (int i = 0; i < count; i++) {
        uintptr_t snap = rd<uintptr_t>(list + 0x20 + i * 8);
        if (!snap) continue;
        uintptr_t move = rd<uintptr_t>(snap + Off::kPlayerSnapshot_Move);
        if (!move) continue;

        Vec3 pos = rd<Vec3>(move + Off::kMovement_Position);
        
        if (pos.x != 0 || pos.y != 0) {
            CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
            // Рисуем квадрат в центре для теста
            CGContextStrokeRect(ctx, CGRectMake(Off::kScreenW/2 - 25, Off::kScreenH/2 - 25, 50, 50));
        }
    }
}
@end

static ESPOverlayView* g_overlay = nil;

static void install_overlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_overlay) return;
        UIWindow* win = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        win.windowLevel = UIWindowLevelStatusBar + 100;
        win.backgroundColor = [UIColor clearColor];
        win.rootViewController = [UIViewController new];
        g_overlay = [[ESPOverlayView alloc] initWithFrame:win.bounds];
        [win.rootViewController.view addSubview:g_overlay];
        win.hidden = NO;
    });
}

%ctor {
    install_overlay();
}
