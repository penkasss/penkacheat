#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <string.h>
#import <dlfcn.h>

// === НАШИ ОФФСЕТЫ ===
namespace Off {
    constexpr uintptr_t kCam_UnityCamera            = 0xB8;  
    constexpr uintptr_t kFPSCamera_PlayerController = 0x130; 
    constexpr uintptr_t kPlayer_LocalList           = 0xA8;
    constexpr uintptr_t kCam_EulerAngles            = 0xE8;
    
    constexpr uintptr_t kRVA_GetCamera             = 0x27629BC; 
    constexpr uintptr_t kRVA_WorldToCam            = 0x63E0680; 
    constexpr uintptr_t kRVA_ProjMatrix            = 0x63E0760;
}

struct Vec3 { float x, y, z; };
struct Matrix4x4 { float m[16]; };

static uintptr_t g_base = 0;
static uintptr_t g_cam_instance = 0;
static bool g_esp_enabled = false;
static bool g_spinner_enabled = false;
static float g_spinner_yaw = 0.0f;
static bool g_init_attempted = false;

static void* g_method_get_transform = NULL;
static void* g_method_get_pos = NULL;

// API IL2CPP
typedef void* (*il2cpp_domain_get_t)(void);
typedef void** (*il2cpp_domain_get_assemblies_t)(void* domain, size_t* size);
typedef void* (*il2cpp_assembly_get_image_t)(void* assembly);
typedef void* (*il2cpp_class_from_name_t)(void* image, const char* namespaze, const char* name);
typedef void* (*il2cpp_class_get_method_from_name_t)(void* klass, const char* name, int argsCount);

void* GetMethodInfo(const char* namespaze, const char* className, const char* methodName, int argsCount) {
    void* handle = dlopen("UnityFramework", RTLD_LAZY);
    if (!handle) return NULL;
    
    auto domain_get = (il2cpp_domain_get_t)dlsym(handle, "il2cpp_domain_get");
    auto domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(handle, "il2cpp_domain_get_assemblies");
    auto assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(handle, "il2cpp_assembly_get_image");
    auto class_from_name = (il2cpp_class_from_name_t)dlsym(handle, "il2cpp_class_from_name");
    auto class_get_method_from_name = (il2cpp_class_get_method_from_name_t)dlsym(handle, "il2cpp_class_get_method_from_name");
    
    if (!domain_get || !domain_get_assemblies || !assembly_get_image || !class_from_name || !class_get_method_from_name) return NULL;
    
    void* domain = domain_get();
    if (!domain) return NULL;
    
    size_t assemblyCount = 0;
    void** assemblies = domain_get_assemblies(domain, &assemblyCount);
    
    for (size_t i = 0; i < assemblyCount; i++) {
        void* image = assembly_get_image(assemblies[i]);
        if (!image) continue;
        
        void* klass = class_from_name(image, namespaze, className);
        if (klass) {
            void* method = class_get_method_from_name(klass, methodName, argsCount);
            if (method) return method;
        }
    }
    return NULL;
}

static uintptr_t module_base(const char* name) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *image_name = _dyld_get_image_name(i);
        if (image_name && strstr(image_name, name)) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

template<typename T> static T rd(uintptr_t a, T fb = T{}) {
    if (a < 0x10000) return fb;
    T v;
    vm_size_t size = sizeof(T);
    vm_size_t out_size = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)a, size, (vm_address_t)&v, &out_size);
    if (kr != KERN_SUCCESS || out_size != size) return fb;
    return v;
}

static bool wr(uintptr_t a, void* val, size_t size) {
    if (a < 0x10000) return false;
    return vm_write(mach_task_self(), (vm_address_t)a, (vm_offset_t)val, (mach_msg_type_number_t)size) == KERN_SUCCESS;
}

// === UI КОД ===
@interface PassThroughView : UIView @end
@implementation PassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface PassThroughWindow : UIWindow @end
@implementation PassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface OverlayRootController : UIViewController @end
@implementation OverlayRootController
- (void)loadView {
    PassThroughView *view = [[PassThroughView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    view.backgroundColor = UIColor.clearColor;
    self.view = view;
}
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface PenkasssOverlay : UIView
@property(nonatomic,strong) UIButton *floatingButton;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIView *content;
@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic) NSInteger selectedTab;
@end

@implementation PenkasssOverlay

static UIColor *AccentColor(void) {
    return [UIColor colorWithRed:0.60 green:0.40 blue:1.00 alpha:1.0];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        [self buildFloatingButton];
        [self buildPanel];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrame:)];
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)buildFloatingButton {
    self.floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.floatingButton.frame = CGRectMake(20, 54, 46, 46);
    self.floatingButton.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.96];
    self.floatingButton.layer.cornerRadius = 23;
    self.floatingButton.layer.borderWidth = 1.5;
    self.floatingButton.layer.borderColor = AccentColor().CGColor;
    [self.floatingButton setImage:[UIImage systemImageNamed:@"shield.lefthalf.filled"] forState:UIControlStateNormal];
    self.floatingButton.tintColor = AccentColor();
    [self.floatingButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatingButton];
}

- (void)buildPanel {
    CGFloat width = MIN(340.0, self.bounds.size.width - 32.0);
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(16, 112, width, 330)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.97];
    self.panel.layer.cornerRadius = 12;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1].CGColor;
    self.panel.hidden = YES;
    [self addSubview:self.panel];

    NSArray<NSString *> *titles = @[@"Visual", @"Aim", @"Misc"];
    CGFloat tabWidth = width / titles.count;
    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *tab = [UIButton buttonWithType:UIButtonTypeSystem];
        tab.frame = CGRectMake(i * tabWidth, 8, tabWidth, 34);
        tab.tag = 100 + i;
        tab.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [tab setTitle:titles[i] forState:UIControlStateNormal];
        [tab addTarget:self action:@selector(selectTab:) forControlEvents:UIControlEventTouchUpInside];
        [self.panel addSubview:tab];
    }

    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(12, 46, width - 24, 1)];
    separator.backgroundColor = [UIColor colorWithWhite:0.28 alpha:1];
    [self.panel addSubview:separator];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 286, width - 28, 30)];
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.statusLabel.textColor = [UIColor colorWithRed:0.55 green:0.9 blue:0.65 alpha:1];
    self.statusLabel.numberOfLines = 2;
    [self.panel addSubview:self.statusLabel];

    self.content = [[UIView alloc] initWithFrame:CGRectMake(0, 54, width, 224)];
    [self.panel addSubview:self.content];
    [self refreshTab];
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
}

- (void)selectTab:(UIButton *)sender {
    self.selectedTab = sender.tag - 100;
    [self refreshTab];
}

- (void)refreshTab {
    [self.content.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *tab = [self.panel viewWithTag:100 + i];
        [tab setTitleColor:(i == self.selectedTab ? UIColor.whiteColor : UIColor.grayColor) forState:UIControlStateNormal];
    }

    if (self.selectedTab == 0) {
        [self addSwitchWithTitle:@"ESP Box" isOn:g_esp_enabled action:@selector(toggleEsp:)];
    } else if (self.selectedTab == 1) {
        [self addSwitchWithTitle:@"Spinbot 360" isOn:g_spinner_enabled action:@selector(toggleSpin:)];
    } else {
        UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(18, 14, self.content.bounds.size.width - 36, 112)];
        note.text = @"PENKASSS CLIENT\nBypass: Active\nBuild: 2.07 F1";
        note.textColor = [UIColor colorWithWhite:0.82 alpha:1];
        note.numberOfLines = 0;
        [self.content addSubview:note];
    }
}

- (void)addSwitchWithTitle:(NSString *)title isOn:(BOOL)isOn action:(SEL)action {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(18, 14, self.content.bounds.size.width - 90, 30)];
    label.text = title;
    label.textColor = UIColor.whiteColor;
    [self.content addSubview:label];

    UISwitch *control = [[UISwitch alloc] initWithFrame:CGRectMake(self.content.bounds.size.width - 66, 11, 52, 32)];
    control.onTintColor = AccentColor();
    control.on = isOn;
    [control addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self.content addSubview:control];
}

- (void)toggleEsp:(UISwitch *)sender {
    g_esp_enabled = sender.isOn;
    [self initGamePointers];
}

- (void)toggleSpin:(UISwitch *)sender {
    g_spinner_enabled = sender.isOn;
    [self initGamePointers];
}

- (void)initGamePointers {
    if (g_init_attempted) return;
    g_init_attempted = true;
    if (!g_base) g_base = module_base("UnityFramework");
    if (g_base && !g_cam_instance) {
        typedef void* (*GetCamFunc)(void*);
        g_cam_instance = (uintptr_t)((GetCamFunc)(g_base + Off::kRVA_GetCamera))(NULL);
    }
    if (!g_method_get_transform) g_method_get_transform = GetMethodInfo("UnityEngine", "Component", "get_transform", 0);
    if (!g_method_get_pos) g_method_get_pos = GetMethodInfo("UnityEngine", "Transform", "get_position", 0);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.panel.hidden && CGRectContainsPoint(self.panel.frame, point)) return YES;
    if (CGRectContainsPoint(self.floatingButton.frame, point)) return YES;
    return NO;
}

- (void)onFrame:(CADisplayLink *)link {
    [self setNeedsDisplay];
    
    if (g_esp_enabled || g_spinner_enabled) {
        [self initGamePointers];
    }
    
    if (g_spinner_enabled && g_cam_instance) {
        g_spinner_yaw += 15.0f;
        if (g_spinner_yaw > 360.0f) g_spinner_yaw -= 360.0f;
        Vec3 angles = { 0.0f, g_spinner_yaw, 0.0f };
        wr(g_cam_instance + Off::kCam_EulerAngles, &angles, sizeof(Vec3));
    }
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGSize screen = self.bounds.size;

    if (!g_esp_enabled || !g_base || !g_cam_instance) return;

    uintptr_t unity_cam = rd<uintptr_t>(g_cam_instance + Off::kCam_UnityCamera);
    if (!unity_cam) return;

    typedef void (*GetMatFunc)(void*, Matrix4x4*);
    Matrix4x4 view = {}, proj = {};
    ((GetMatFunc)(g_base + Off::kRVA_WorldToCam))((void*)unity_cam, &view);
    ((GetMatFunc)(g_base + Off::kRVA_ProjMatrix))((void*)unity_cam, &proj);
    
    if (view.m[0] == 0.0f || proj.m[0] == 0.0f) return;

    Matrix4x4 vp;
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            vp.m[i*4+j] = 0;
            for (int k = 0; k < 4; k++) vp.m[i*4+j] += view.m[i*4+k] * proj.m[k*4+j];
        }
    }

    uintptr_t localPlayer = rd<uintptr_t>(g_cam_instance + Off::kFPSCamera_PlayerController);
    if (!localPlayer) return;
    
    uintptr_t localList = rd<uintptr_t>(localPlayer + Off::kPlayer_LocalList);
    if (!localList) return;

    uintptr_t list = rd<uintptr_t>(localList + 0x10);
    int count = rd<int>(localList + 0x18);

    if (count <= 0 || count > 100 || !list) return;

    CGContextSetLineWidth(ctx, 1.5);
    CGContextSetStrokeColorWithColor(ctx, [UIColor greenColor].CGColor);

    typedef void (*GetTransformFunc)(void*, void*);
    typedef void (*GetPosFunc)(void*, Vec3*, void*);

    int drawn = 0;
    for (int i = 0; i < count; i++) {
        uintptr_t ctrl = rd<uintptr_t>(list + 0x20 + i * 8); 
        if (!ctrl || ctrl == localPlayer) continue;
        
        void* trans = NULL;
        if (g_method_get_transform) {
            void* func_t = *(void**)g_method_get_transform;
            ((GetTransformFunc)func_t)((void*)ctrl, &trans);
        }
        if (!trans) continue;

        Vec3 pos = {};
        if (g_method_get_pos) {
            void* func_p = *(void**)g_method_get_pos;
            ((GetPosFunc)func_p)(trans, &pos, g_method_get_pos);
        }

        if (pos.x == 0 && pos.y == 0 && pos.z == 0) continue;

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
        drawn++;
    }
    
    self.statusLabel.text = [NSString stringWithFormat:@"WH ON | Drawn: %d", drawn];
}
@end

static PassThroughWindow *g_overlayWindow;
static PenkasssOverlay *g_diagnosticOverlay;

static void install_overlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_overlayWindow) return;
        UIWindowScene *activeScene = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }
        if (!activeScene) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ install_overlay(); });
            return;
        }
        g_overlayWindow = [[PassThroughWindow alloc] initWithWindowScene:activeScene];
        g_overlayWindow.frame = activeScene.coordinateSpace.bounds;
        g_overlayWindow.windowLevel = UIWindowLevelAlert + 1;
        g_overlayWindow.backgroundColor = UIColor.clearColor;
        g_overlayWindow.rootViewController = [OverlayRootController new];
        g_diagnosticOverlay = [[PenkasssOverlay alloc] initWithFrame:g_overlayWindow.bounds];
        [g_overlayWindow.rootViewController.view addSubview:g_diagnosticOverlay];
        g_overlayWindow.hidden = NO;
    });
}

%ctor {
    @autoreleasepool {
        install_overlay();
    }
}
