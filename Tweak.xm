#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

namespace Off {
    constexpr uintptr_t kEntityList      = 0x0;
    constexpr uintptr_t kEntityListCount = 0x0;
    constexpr uintptr_t kEntityStride    = 0x8;
    constexpr uintptr_t kEntity_Health   = 0x0;
    constexpr uintptr_t kEntity_Team     = 0x0;
    constexpr uintptr_t kEntity_Position = 0x0;
    constexpr uintptr_t kEntity_Alive    = 0x0;
    constexpr uintptr_t kViewMatrix      = 0x0;
    constexpr uintptr_t kLocalPlayer     = 0x0;
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

static bool w2s(const float* m, const Vec3& w, Vec2& o) {
    float cx = w.x*m[0]+w.y*m[4]+w.z*m[8]+m[12];
    float cy = w.x*m[1]+w.y*m[5]+w.z*m[9]+m[13];
    float cw = w.x*m[3]+w.y*m[7]+w.z*m[11]+m[15];
    if (cw < 0.001f) return false;
    o.x = (cx/cw*0.5f+0.5f)*Off::kScreenW;
    o.y = (1.0f-(cy/cw*0.5f+0.5f))*Off::kScreenH;
    return true;
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
        g_base = module_base("StandChillow");
        if (!g_base) g_base = module_base("UnityFramework");
        if (!g_base) return;
    }
    uintptr_t list = rd<uintptr_t>(g_base + Off::kEntityList);
    if (!list) return;
    int32_t cnt = rd<int32_t>(g_base + Off::kEntityListCount);
    if (cnt <= 0 || cnt > 256) return;
    uintptr_t local = rd<uintptr_t>(g_base + Off::kLocalPlayer);
    if (!local) return;
    int32_t lteam = rd<int32_t>(local + Off::kEntity_Team);
    float mat[16];
    memcpy(mat, (void*)(g_base + Off::kViewMatrix), sizeof(mat));

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 1.5);

    for (int i = 0; i < cnt; ++i) {
        uintptr_t e = rd<uintptr_t>(list + i*Off::kEntityStride);
        if (!e || e == local) continue;
        if (!rd<uint8_t>(e + Off::kEntity_Alive)) continue;
        if (rd<int32_t>(e + Off::kEntity_Team) == lteam) continue;
        Vec3 p = rd<Vec3>(e + Off::kEntity_Position);
        if (p.x==0 && p.y==0 && p.z==0) continue;
        float hp = rd<float>(e + Off::kEntity_Health);
        if (hp <= 0 || hp > 1000) continue;

        Vec3 head = {p.x, p.y + 1.75f, p.z};
        Vec2 sf, sh;
        if (!w2s(mat, p, sf) || !w2s(mat, head, sh)) continue;
        float h = sf.y - sh.y;
        if (h < 4 || h > 1500) continue;
        float w = h * 0.45f;
        CGRect r = CGRectMake(sh.x - w*0.5f, sh.y, w, h);
        CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
        CGContextStrokeRect(ctx, r);
        float hb = h * (hp / 100.0f);
        CGContextSetFillColorWithColor(ctx, [UIColor greenColor].CGColor);
        CGContextFillRect(ctx, CGRectMake(r.origin.x-4, r.origin.y + (h-hb), 3, hb));
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
