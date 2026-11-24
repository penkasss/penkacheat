#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

namespace Off {
    // Цепочка оффсетов, которую мы нашли
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
@end

@implementation ESPOverlayView
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    return self;
}
- (void)tick { [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    if (!g_base) {
        g_base = module_base("UnityFramework");
        if (!g_base) return;
    }
    
    // Вызов метода betm() из дампа (RVA: 0x27629BC) для получения камеры
    uintptr_t betm_func = g_base + 0x27629BC; 
    typedef void* (*GetCameraFunc)(void);
    GetCameraFunc get_camera = (GetCameraFunc)betm_func;
    uintptr_t cam = (uintptr_t)get_camera();

    if (!cam) return;

    // Идем по цепочке оффсетов
    uintptr_t localPlayer = rd<uintptr_t>(cam + Off::kFPSCamera_PlayerController);
    if (!localPlayer) return;

    uintptr_t netCtrl = rd<uintptr_t>(localPlayer + Off::kPlayer_NetworkController);
    if (!netCtrl) return;

    uintptr_t list = rd<uintptr_t>(netCtrl + Off::kNetwork_PlayerList);
    if (!list) return;
    
    // В C# массивах длина лежит по смещению 0x18
    int count = rd<int>(list + 0x18);
    if (count <= 0 || count > 64) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 2.0);

    for (int i = 0; i < count; i++) {
        // Элементы массива начинаются с 0x20
        uintptr_t snap = rd<uintptr_t>(list + 0x20 + i * 8);
        if (!snap) continue;

        uintptr_t move = rd<uintptr_t>(snap + Off::kPlayerSnapshot_Move);
        if (!move) continue;

        Vec3 pos = rd<Vec3>(move + Off::kMovement_Position);
        
        // Проверка, что координаты не нулевые
        if (pos.x != 0 || pos.y != 0) {
            CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
            // Временно рисуем квадрат в центре экрана, чтобы проверить, 
            // что код доходит до чтения координат.
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
