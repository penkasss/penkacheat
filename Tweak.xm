#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

namespace Off {
    constexpr uintptr_t kFPSCamera_PlayerController = 0x130;
    constexpr uintptr_t kPlayer_NetworkController  = 0x110;
    constexpr uintptr_t kNetwork_PlayerList        = 0x78;
    constexpr uintptr_t kPlayerSnapshot_Move       = 0x18;
    constexpr uintptr_t kMovement_Position         = 0x14;
    
    constexpr uintptr_t kRVA_GetCamera             = 0x27629BC;
    constexpr uintptr_t kRVA_WorldToCam            = 0x63E0604;
    constexpr uintptr_t kRVA_ProjMatrix            = 0x63E06E4;
}

struct Vec3 { float x, y, z; };
struct Matrix4x4 { float m[16]; };

static uintptr_t g_base = 0;
static bool g_esp_enabled = false;

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

// Вью, которое пропускает тапы в игру
@interface PassThroughView : UIView @end
@implementation PassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}
@end

// Окно, которое пропускает тапы в игру
@interface PassThroughWindow : UIWindow @end
@implementation PassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}
@end

@interface OverlayViewController : UIViewController @end
@implementation OverlayViewController
- (void)loadView {
    self.view = [[PassThroughView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.userInteractionEnabled = YES;
}
@end

@interface CustomCheckbox : UIButton @end
@implementation CustomCheckbox
- (instancetype)initWithFrame:(CGRect)frame title:(NSString*)title {
    self = [super initWithFrame:frame];
    [self setTitle:title forState:UIControlStateNormal];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.titleLabel.font = [UIFont systemFontOfSize:12];
    self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [self setImage:[UIImage systemImageNamed:@"circle"] forState:UIControlStateNormal];
    [self setImage:[UIImage systemImageNamed:@"checkmark.circle.fill"] forState:UIControlStateSelected];
    self.tintColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    [self addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)toggle { self.selected = !self.selected; }
- (void)layoutSubviews {
    [super layoutSubviews];
    self.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
    self.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, -5);
}
@end

@interface PenkasssMenu : UIView
@property (nonatomic, strong) UIView* mainPanel;
@property (nonatomic, strong) UIButton* floatingBtn;
@property (nonatomic, strong) CADisplayLink* link;
@end

@implementation PenkasssMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor clearColor];
    
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    self.floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingBtn.frame = CGRectMake(20, 50, 45, 45);
    self.floatingBtn.backgroundColor = [UIColor blackColor];
    self.floatingBtn.layer.cornerRadius = 22.5;
    self.floatingBtn.layer.borderWidth = 1.0;
    self.floatingBtn.layer.borderColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0].CGColor;
    [self.floatingBtn setTitle:@"P" forState:UIControlStateNormal];
    [self.floatingBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.floatingBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatingBtn];
    
    self.mainPanel = [[UIView alloc] initWithFrame:CGRectMake(40, 110, 320, 300)];
    self.mainPanel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.mainPanel.layer.cornerRadius = 10;
    self.mainPanel.layer.borderWidth = 1.0;
    self.mainPanel.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    self.mainPanel.hidden = YES;
    [self addSubview:self.mainPanel];
    
    NSArray* tabs = @[@"Visual", @"Aim", @"Misc"];
    for (int i = 0; i < 3; i++) {
        UIButton* tab = [UIButton buttonWithType:UIButtonTypeSystem];
        tab.frame = CGRectMake(i*(320/3.0), 10, 320/3.0, 30);
        [tab setTitle:tabs[i] forState:UIControlStateNormal];
        [tab setTitleColor:(i==0)?[UIColor whiteColor]:[UIColor grayColor] forState:UIControlStateNormal];
        tab.titleLabel.font = [UIFont systemFontOfSize:12];
        [tab addTarget:self action:@selector(switchTab:) forControlEvents:UIControlEventTouchUpInside];
        tab.tag = 100 + i;
        [self.mainPanel addSubview:tab];
    }
    
    UIView* line = [[UIView alloc] initWithFrame:CGRectMake(10, 45, 300, 1)];
    line.backgroundColor = [UIColor darkGrayColor];
    [self.mainPanel addSubview:line];
    
    UIView* contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 50, 320, 250)];
    [self.mainPanel addSubview:contentView];
    
    CustomCheckbox* cbEsp = [[CustomCheckbox alloc] initWithFrame:CGRectMake(20, 10, 280, 20) title:@"ESP Box"];
    [cbEsp addTarget:self action:@selector(togEsp) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:cbEsp];
    
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}

- (void)switchTab:(UIButton*)sender {
    for (int i = 100; i <= 102; i++) {
        UIButton* b = [self.mainPanel viewWithTag:i];
        [b setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    }
    [sender setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
}

- (void)togEsp { g_esp_enabled = !g_esp_enabled; }
- (void)toggleMenu { self.mainPanel.hidden = !self.mainPanel.hidden; }
- (void)tick { [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    if (!g_esp_enabled) return;
    if (!g_base) g_base = module_base("UnityFramework");
    if (!g_base) return;

    typedef void* (*GetCamFunc)(void);
    uintptr_t cam = (uintptr_t)((GetCamFunc)(g_base + Off::kRVA_GetCamera))();
    if (!cam) return;

    typedef Matrix4x4 (*GetMatFunc)(void*);
    Matrix4x4 view = ((GetMatFunc)(g_base + Off::kRVA_WorldToCam))((void*)cam);
    Matrix4x4 proj = ((GetMatFunc)(g_base + Off::kRVA_ProjMatrix))((void*)cam);
    Matrix4x4 vp;
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            vp.m[i*4+j] = 0;
            for (int k = 0; k < 4; k++) vp.m[i*4+j] += view.m[i*4+k] * proj.m[k*4+j];
        }
    }

    uintptr_t localPlayer = rd<uintptr_t>(cam + Off::kFPSCamera_PlayerController);
    if (!localPlayer) return;
    uintptr_t netCtrl = rd<uintptr_t>(localPlayer + Off::kPlayer_NetworkController);
    if (!netCtrl) return;
    uintptr_t list = rd<uintptr_t>(netCtrl + Off::kNetwork_PlayerList);
    if (!list) return;

    int count = rd<int>(list + 0x18);
    if (count <= 0 || count > 64) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 1.5);
    CGContextSetStrokeColorWithColor(ctx, [UIColor greenColor].CGColor);
    CGSize screen = [UIScreen mainScreen].bounds.size;

    for (int i = 0; i < count; i++) {
        uintptr_t snap = rd<uintptr_t>(list + 0x20 + i * 8);
        if (!snap) continue;
        uintptr_t move = rd<uintptr_t>(snap + Off::kPlayerSnapshot_Move);
        if (!move) continue;
        Vec3 pos = rd<Vec3>(move + Off::kMovement_Position);
        if (pos.x == 0 && pos.y == 0) continue;

        Vec3 head = { pos.x, pos.y + 1.8f, pos.z };
        Vec3 foot = { pos.x, pos.y, pos.z };
        
        float cw_h = head.x*vp.m[3] + head.y*vp.m[7] + head.z*vp.m[11] + vp.m[15];
        if (cw_h < 0.1f) continue;
        float nx_h = (head.x*vp.m[0] + head.y*vp.m[4] + head.z*vp.m[8] + vp.m[12]) / cw_h;
        float ny_h = (head.x*vp.m[1] + head.y*vp.m[5] + head.z*vp.m[9] + vp.m[13]) / cw_h;
        float sx_h = (screen.width / 2.0f) * (1.0f + nx_h);
        float sy_h = (screen.height / 2.0f) * (1.0f - ny_h);

        float cw_f = foot.x*vp.m[3] + foot.y*vp.m[7] + foot.z*vp.m[11] + vp.m[15];
        if (cw_f < 0.1f) continue;
        float ny_f = (foot.x*vp.m[1] + foot.y*vp.m[5] + foot.z*vp.m[9] + vp.m[13]) / cw_f;
        float sy_f = (screen.height / 2.0f) * (1.0f - ny_f);

        float h = sy_f - sy_h;
        if (h < 5) continue; 
        float w = h * 0.5f;
        
        CGContextStrokeRect(ctx, CGRectMake(sx_h - w/2, sy_h, w, h));
    }
}
@end

static PenkasssMenu* g_overlay = nil;
static PassThroughWindow* g_window = nil;

static void install_overlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_overlay) return;

        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (s.activationState == UISceneActivationStateForegroundActive && [s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        
        // Если игра еще не загрузила сцену — ждем полсекунды и пробуем снова
        if (!scene) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                install_overlay();
            });
            return;
        }

        g_window = [[PassThroughWindow alloc] initWithWindowScene:scene];
        g_window.frame = [UIScreen mainScreen].bounds;
        g_window.windowLevel = UIWindowLevelStatusBar + 100;
        g_window.backgroundColor = [UIColor clearColor];
        
        OverlayViewController *vc = [[OverlayViewController alloc] init];
        g_window.rootViewController = vc;
        
        g_overlay = [[PenkasssMenu alloc] initWithFrame:g_window.bounds];
        [vc.view addSubview:g_overlay];
        
        g_window.hidden = NO; // Не делаем KeyAndVisible, чтобы не ломать ввод игры
    });
}
%ctor { install_overlay(); }
