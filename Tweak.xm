#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// === МАГИЯ ДЛЯ ПРОПУСКА НАЖАТИЙ ===
@interface PassThroughWindow : UIWindow
@end
@implementation PassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}
@end

// === КАСТОМНЫЙ ЧЕКБОКС ===
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
- (void)toggle {
    self.selected = !self.selected;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
    self.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, -5);
}
@end

// === ГЛАВНОЕ МЕНЮ ===
@interface PenkasssMenu : UIView
@property (nonatomic, strong) UIView* mainPanel;
@property (nonatomic, strong) UIButton* floatingBtn;
@property (nonatomic, assign) BOOL isMenuOpen;
@end

@implementation PenkasssMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;
    
    // Кнопка вызова
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
    
    // Панель меню
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
    
    // Линия
    UIView* line = [[UIView alloc] initWithFrame:CGRectMake(10, 45, 300, 1)];
    line.backgroundColor = [UIColor darkGrayColor];
    [self.mainPanel addSubview:line];
    
    // Заголовки
    UILabel* col1 = [[UILabel alloc] initWithFrame:CGRectMake(20, 55, 90, 15)];
    col1.text = @"Player";
    col1.textColor = [UIColor grayColor];
    col1.font = [UIFont systemFontOfSize:11];
    [self.mainPanel addSubview:col1];
    
    UILabel* col2 = [[UILabel alloc] initWithFrame:CGRectMake(120, 55, 90, 15)];
    col2.text = @"Labels";
    col2.textColor = [UIColor grayColor];
    col2.font = [UIFont systemFontOfSize:11];
    [self.mainPanel addSubview:col2];
    
    UILabel* col3 = [[UILabel alloc] initWithFrame:CGRectMake(220, 55, 90, 15)];
    col3.text = @"World";
    col3.textColor = [UIColor grayColor];
    col3.font = [UIFont systemFontOfSize:11];
    [self.mainPanel addSubview:col3];
    
    // Чекбоксы
    NSArray* pChecks = @[@"Line", @"Skeleton", @"Health", @"Distance", @"Target Line"];
    for (int i = 0; i < pChecks.count; i++) {
        CustomCheckbox* cb = [[CustomCheckbox alloc] initWithFrame:CGRectMake(20, 75 + (i * 30), 100, 20) title:pChecks[i]];
        if (i < 2) cb.selected = YES;
        [self.mainPanel addSubview:cb];
    }
    
    NSArray* lChecks = @[@"Name", @"Enemy Count"];
    for (int i = 0; i < lChecks.count; i++) {
        CustomCheckbox* cb = [[CustomCheckbox alloc] initWithFrame:CGRectMake(120, 75 + (i * 30), 100, 20) title:lChecks[i]];
        [self.mainPanel addSubview:cb];
    }
    
    NSArray* wChecks = @[@"Vehicles", @"Tomb Box", @"Throwable"];
    for (int i = 0; i < wChecks.count; i++) {
        CustomCheckbox* cb = [[CustomCheckbox alloc] initWithFrame:CGRectMake(220, 75 + (i * 30), 100, 20) title:wChecks[i]];
        if (i < 3) cb.selected = YES;
        [self.mainPanel addSubview:cb];
    }
    
    return self;
}

- (void)toggleMenu {
    self.isMenuOpen = !self.isMenuOpen;
    if (self.isMenuOpen) {
        self.mainPanel.hidden = NO;
        [UIView animateWithDuration:0.2 animations:^{
            self.mainPanel.alpha = 1.0;
        }];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self.mainPanel.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.mainPanel.hidden = YES;
        }];
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
