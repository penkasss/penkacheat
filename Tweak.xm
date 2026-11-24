#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

// === ОФФСЕТЫ ===
namespace Off {
    constexpr uintptr_t kFPSCamera_PlayerController = 0x130;
    constexpr uintptr_t kPlayer_NetworkController  = 0x110;
    constexpr uintptr_t kNetwork_PlayerList        = 0x78;
    constexpr uintptr_t kPlayerSnapshot_Move       = 0x18;
    constexpr uintptr_t kMovement_Position         = 0x14;
    constexpr uintptr_t kPlayer_BipedMap           = 0x30;
    constexpr uintptr_t kBiped_Head                = 0x20;
    constexpr uintptr_t kBiped_Neck                = 0x28;
    constexpr uintptr_t kBiped_Hip                 = 0x88;
    constexpr uintptr_t kBiped_LeftFoot            = 0xA0;
    constexpr uintptr_t kBiped_RightFoot           = 0xC0;
    
    // RVA методов
    constexpr uintptr_t kRVA_GetCamera             = 0x27629BC;
    constexpr uintptr_t kRVA_WorldToCam            = 0x63E0604;
    constexpr uintptr_t kRVA_ProjMatrix            = 0x63E06E4;
}

struct Vec3 { float x, y, z; };
struct Vec2 { float x, y; };
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

// Магия для пропуска нажатий
@interface PassThroughWindow : UIWindow
@end
@implementation PassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}
@end

@interface CustomCheckbox : UIButton
@end
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

// === ГЛАВНОЕ МЕНЮ + ОТРИСОВКА ESP ===
@interface PenkasssMenu : UIView
@property (nonatomic, strong) UIView* mainPanel;
@property (nonatomic, strong) UIButton* floatingBtn;
@property (nonatomic, assign) BOOL isMenuOpen;
@property (nonatomic, strong) CADisplayLink* link;
@end

@implementation PenkasssMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;
    
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    // Кнопка
    self.floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingBtn.frame = CGRectMake(20, 100, 50, 50);
    self.floatingBtn.backgroundColor = [UIColor blackColor];
    self.floatingBtn.layer.cornerRadius = 25;
    self.floatingBtn.layer.borderWidth = 1.0;
    self.floatingBtn.layer.borderColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0].CGColor;
    [self.floatingBtn setImage:[UIImage systemImageNamed:@"bolt.shield.fill"] forState:UIControlStateNormal];
    self.floatingBtn.tintColor = [UIColor colorWithRed:0.6 green:0.4 blue:1.0 alpha:1.0];
    [self.floatingBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatingBtn];
    
    // Меню
    self.mainPanel = [[UIView alloc] initWithFrame:CGRectMake(40, 160, 320, 250)];
    self.mainPanel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.mainPanel.layer.cornerRadius = 10;
    self.mainPanel.layer.borderWidth = 1.0;
    self.mainPanel.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    self.mainPanel.hidden = YES;
    self.mainPanel.alpha = 0.0;
    [self addSubview:self.mainPanel];
    
    // Вкладки
    NSArray* tabs = @[@"Visual", @"Aim", @"Misc", @"Style", @"Settings"];
    CGFloat tabWidth = 320 / 5.0;
    for (int i = 0; i < 5; i++) {
        UILabel* tabLabel = [[UILabel alloc] initWithFrame:CGRectMake(i * tabWidth, 10, tabWidth, 30)];
        tabLabel.text = tabs[i];
        tabLabel.textColor = (i == 0) ? [UIColor whiteColor] : [UIColor grayColor];
        tabLabel.textAlignment = NSTextAlignmentCenter;
        tabLabel.font = [UIFont systemFontOfSize:10];
        [self.mainPanel addSubview:tabLabel];
    }
    
    UIView* line = [[UIView alloc] initWithFrame:CGRectMake(10, 45, 300, 1)];
    line.backgroundColor = [UIColor darkGrayColor];
    [self.mainPanel addSubview:line];
    
    // Чекбоксы
    CustomCheckbox* cb1 = [[CustomCheckbox alloc] initWithFrame:CGRectMake(20, 60, 150, 20) title:@"ESP Box"];
    [cb1 addTarget:self action:@selector(toggleESP) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:cb1];
    
    return self;
}

- (void)toggleESP {
    g_esp_enabled = !g_esp_enabled;
}

- (void)toggleMenu {
    self.isMenuOpen = !self.isMenuOpen;
    if (self.isMenuOpen) {
        self.mainPanel.hidden = NO;
        [UIView animateWithDuration:0.2 animations:^{ self.mainPanel.alpha = 1.0; }];
    } else {
        [UIView animateWithDuration:0.2 animations:^{ self.mainPanel.alpha = 0.0; } completion:^(BOOL f){ self.mainPanel.hidden = YES; }];
    }
}

- (void)tick { [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    if (!g_esp_enabled) return;
    if (!g_base) {
        g_base = module_base("UnityFramework");
        if (!g_base) return;
    }

    // 1. Получаем камеру
    typedef void* (*GetCamFunc)(void);
    uintptr_t cam = ((GetCamFunc)(g_base + Off::kRVA_GetCamera))();
    if (!cam) return;

    // 2. Получаем матрицы
    typedef Matrix4x4 (*GetMatFunc)(void*);
    Matrix4x4 view = ((GetMatFunc)(g_base + Off::kRVA_WorldToCam))((void*)cam);
    Matrix4x4 proj = ((GetMatFunc)(g_base + Off::kRVA_ProjMatrix))((void*)cam);

    // Перемножаем матрицы (View * Proj)
    Matrix4x4 vp;
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            vp.m[i*4+j] = 0;
            for (int k = 0; k < 4; k++) {
                vp.m[i*4+j] += view.m[i*4+k] * proj.m[k*4+j];
            }
        }
    }

    // 3. Идем по игрокам
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
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0].CGColor);

    CGSize screen = [UIScreen mainScreen].bounds.size;

    for (int i = 0; i < count; i++) {
        uintptr_t snap = rd<uintptr_t>(list + 0x20 + i * 8);
        if (!snap) continue;

        // Позиция для квадрата
        uintptr_t move = rd<uintptr_t>(snap + Off::kPlayerSnapshot_Move);
        if (!move) continue;
        Vec3 pos = rd<Vec3>(move + Off::kMovement_Position);
        if (pos.x == 0 && pos.y == 0) continue;

        // Скелет (берем голову из BipedMap)
        // Примечание: в PlayerSnapshot может не быть прямого доступа к BipedMap, 
        // поэтому пока рисуем квадрат от ног до головы, используя координату Y + 1.8
        Vec3 head = { pos.x, pos.y + 1.8f, pos.z };
        Vec3 foot = { pos.x, pos.y, pos.z };

        // W2S
        float clip_w = head.x*vp.m[3] + head.y*vp.m[7] + head.z*vp.m[11] + vp.m[15];
        if (clip_w < 0.1f) continue;

        float ndc_x = (head.x*vp.m[0] + head.y*vp.m[4] + head.z*vp.m[8] + vp.m[12]) / clip_w;
        float ndc_y = (head.x*vp.m[1] + head.y*vp.m[5] + head.z*vp.m[9] + vp.m[13]) / clip_w;

        float screen_x = (screen.width / 2.0f) * (1.0f + ndc_x);
        float screen_y = (screen.height / 2.0f) * (1.0f - ndc_y);

        // Рисуем квадрат 30x50 (просто для теста)
        CGContextStrokeRect(ctx, CGRectMake(screen_x - 15, screen_y, 30, 50));
    }
}
@end

static PenkasssMenu* g_overlay = nil;

static void install_overlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_overlay) return;
        UIWindow* win = [[PassThroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        win.windowLevel = UIWindowLevelStatusBar + 100;
        win.backgroundColor = [UIColor clearColor];
        win.rootViewController = [UIViewController new];
        g_overlay = [[PenkasssMenu alloc] initWithFrame:win.bounds];
        [win.rootViewController.view addSubview:g_overlay];
        win.hidden = NO;
    });
}

%ctor {
    install_overlay();
}
