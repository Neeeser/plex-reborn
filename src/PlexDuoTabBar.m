// Tab bar on the Duo's vertical bar, and consistent tab icon sizes.
//
// iOS 27.1 moves a UITabBarController's tabs into the Duo's vertical bar (on
// the outer screen, and on the inner screen in landscape). Plex 8.45 does not
// use UITabBarController: it places a standalone tab bar (PMSafeAreaTabBar)
// inside its own screen, so the system leaves it at the bottom. Whenever the
// system reports a vertical bar (UITraitCollection.verticalBarEdge), this file
// hides Plex's bar and shows the same tabs as a column of icons in the
// vertical bar's strip, below the clock and status icons. Choosing a tab goes
// through Plex's own tab bar and its delegate, so Plex's navigation is unchanged.
//
// Plex's tab images come in different sizes; the floating tab bar draws them at
// their natural size, so some icons fill the whole button and crowd their
// labels. Every tab image is redrawn once into the same square.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Close to the system vertical tab bar: a 48 pt capsule with 48 x 54 pt tab
// cells, icons only (Apple's iPhone Duo design kit, as read by third parties).
static const CGFloat PLXTabIconSide = 24.0;
static const CGFloat PLXRailWidth = 48.0;
static const CGFloat PLXRailButtonHeight = 54.0;
// The clock and status icons occupy the top of the vertical bar's strip.
static const CGFloat PLXRailTopClearance = 160.0;

static const void *PLXNormalizedImageKey = &PLXNormalizedImageKey;
static const void *PLXRailKey = &PLXRailKey;

static UIImage *PLXSquareIcon(UIImage *image) {
    if (!image || objc_getAssociatedObject(image, PLXNormalizedImageKey)) return image;
    CGSize box = CGSizeMake(PLXTabIconSide, PLXTabIconSide);
    CGFloat scale = MIN(box.width / MAX(image.size.width, 1), box.height / MAX(image.size.height, 1));
    CGSize drawn = CGSizeMake(image.size.width * scale, image.size.height * scale);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:box];
    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake((box.width - drawn.width) / 2, (box.height - drawn.height) / 2, drawn.width, drawn.height)];
    }];
    result = [result imageWithRenderingMode:image.renderingMode];
    objc_setAssociatedObject(result, PLXNormalizedImageKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

static void PLXNormalizeTabImages(UITabBar *tabBar) {
    for (UITabBarItem *item in tabBar.items) {
        UIImage *image = PLXSquareIcon(item.image);
        if (image != item.image) item.image = image;
        UIImage *selected = PLXSquareIcon(item.selectedImage);
        if (selected != item.selectedImage) item.selectedImage = selected;
    }
}

#pragma mark - Rail

@interface PLXTabRail : UIView
@property (nonatomic, weak) UITabBar *tabBar;
@property (nonatomic, strong) UIVisualEffectView *background;
@property (nonatomic, strong) UIView *selectionPlatter;
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@end

@implementation PLXTabRail

- (instancetype)initWithTabBar:(UITabBar *)tabBar {
    if ((self = [super initWithFrame:CGRectZero])) {
        _tabBar = tabBar;
        _buttons = [NSMutableArray array];
        UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        if (@available(iOS 26.0, *)) effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        _background = [[UIVisualEffectView alloc] initWithEffect:effect];
        _background.clipsToBounds = YES;
        _background.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_background];
        _selectionPlatter = [[UIView alloc] init];
        _selectionPlatter.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
        _selectionPlatter.layer.cornerCurve = kCACornerCurveContinuous;
        _selectionPlatter.userInteractionEnabled = NO;
        [_background.contentView addSubview:_selectionPlatter];
    }
    return self;
}

- (void)reloadItems {
    NSArray<UITabBarItem *> *items = self.tabBar.items;
    while (self.buttons.count > items.count) { [self.buttons.lastObject removeFromSuperview]; [self.buttons removeLastObject]; }
    while (self.buttons.count < items.count) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button addTarget:self action:@selector(select:) forControlEvents:UIControlEventPrimaryActionTriggered];
        [self.background.contentView addSubview:button];
        [self.buttons addObject:button];
    }
    UITabBarItem *selected = self.tabBar.selectedItem;
    // Plex colors the selected tab through its bar appearance, not tintColor.
    UIColor *accent = self.tabBar.standardAppearance.stackedLayoutAppearance.selected.iconColor
        ?: [UIColor colorWithRed:0.898 green:0.627 blue:0.051 alpha:1];
    [items enumerateObjectsUsingBlock:^(UITabBarItem *item, NSUInteger i, BOOL *stop) {
        UIButton *button = self.buttons[i];
        BOOL isSelected = item == selected;
        UIImage *image = (isSelected && item.selectedImage) ? item.selectedImage : item.image;
        [button setImage:[PLXSquareIcon(image) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        button.tintColor = isSelected ? accent : [UIColor colorWithWhite:1 alpha:0.9];
        button.accessibilityLabel = item.title;
        button.accessibilityTraits = isSelected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
        button.tag = (NSInteger)i;
    }];
    [self setNeedsLayout];
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(PLXRailWidth, self.buttons.count * PLXRailButtonHeight + 8);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.background.frame = self.bounds;
    self.background.layer.cornerRadius = PLXRailWidth / 2;
    NSUInteger selectedIndex = self.tabBar.selectedItem ? [self.tabBar.items indexOfObject:self.tabBar.selectedItem] : NSNotFound;
    for (UIButton *button in self.buttons) {
        button.frame = CGRectMake(0, 4 + button.tag * PLXRailButtonHeight, PLXRailWidth, PLXRailButtonHeight);
    }
    self.selectionPlatter.hidden = selectedIndex == NSNotFound;
    if (selectedIndex != NSNotFound) {
        self.selectionPlatter.frame = CGRectInset(self.buttons[selectedIndex].frame, 3, 3);
        self.selectionPlatter.layer.cornerRadius = CGRectGetHeight(self.selectionPlatter.frame) / 2;
    }
}

- (void)select:(UIButton *)sender {
    UITabBar *tabBar = self.tabBar;
    if (sender.tag >= (NSInteger)tabBar.items.count) return;
    UITabBarItem *item = tabBar.items[sender.tag];
    tabBar.selectedItem = item;
    if ([tabBar.delegate respondsToSelector:@selector(tabBar:didSelectItem:)]) {
        [tabBar.delegate tabBar:tabBar didSelectItem:item];
    }
    [self reloadItems];
}

@end

#pragma mark - Placement

// The edge of the window where the system's vertical bar is showing, or 0.
static NSInteger PLXVerticalBarEdge(UIView *view) {
    if (@available(iOS 27.1, *)) return view.window ? view.window.traitCollection.verticalBarEdge : 0;
    return 0;
}

static void PLXLayoutRail(UITabBar *tabBar) {
    UIView *host = tabBar.superview;
    UIWindow *window = tabBar.window;
    PLXTabRail *rail = objc_getAssociatedObject(tabBar, PLXRailKey);
    NSInteger edge = PLXVerticalBarEdge(tabBar);
    BOOL useRail = host && window && edge != 0 && tabBar.items.count > 0;

    // Plex hides its tab bar on some screens (the player, full-screen sheets).
    BOOL plexHidesBar = tabBar.isHidden;
    if (!useRail) {
        rail.hidden = YES;
        if (tabBar.alpha == 0 && objc_getAssociatedObject(tabBar, @selector(alpha))) tabBar.alpha = 1;
        objc_setAssociatedObject(tabBar, @selector(alpha), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!rail) {
        rail = [[PLXTabRail alloc] initWithTabBar:tabBar];
        objc_setAssociatedObject(tabBar, PLXRailKey, rail, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (rail.superview != host) [host addSubview:rail];
    [host bringSubviewToFront:rail];

    // Keep Plex's bar in place for its own layout code, but invisible and untouchable.
    tabBar.alpha = 0;
    objc_setAssociatedObject(tabBar, @selector(alpha), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    rail.hidden = plexHidesBar;

    [rail reloadItems];
    UIEdgeInsets safe = window.safeAreaInsets;
    BOOL trailing = edge == 2;
    BOOL rightToLeft = window.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL onRight = trailing != rightToLeft;
    CGFloat strip = onRight ? safe.right : safe.left;
    if (strip < PLXRailWidth) strip = PLXRailWidth + 12;
    CGSize size = rail.intrinsicContentSize;
    // Horizontal position comes from the host's own width, not window
    // coordinates: Plex slides the whole content sideways while its side menu
    // is open, and a window-based position taken then would stick after it closes.
    CGFloat width = CGRectGetWidth(host.bounds);
    CGFloat x = onRight ? width - strip + (strip - size.width) / 2 : (strip - size.width) / 2;
    CGFloat available = CGRectGetHeight(window.bounds) - safe.bottom;
    CGFloat yInWindow = MAX(PLXRailTopClearance, (available - size.height) / 2);
    CGFloat hostTop = [host convertPoint:CGPointZero toView:nil].y;
    rail.frame = CGRectMake(x, yInWindow - hostTop, size.width, size.height);
}

static IMP PLXOrigTabBarLayout;

static void PLXTabBarLayoutSubviews(UITabBar *self, SEL _cmd) {
    PLXNormalizeTabImages(self);
    ((void (*)(id, SEL))PLXOrigTabBarLayout)(self, _cmd);
    PLXLayoutRail(self);
}

static IMP PLXOrigTabBarSetHidden;

static void PLXTabBarSetHidden(UITabBar *self, SEL _cmd, BOOL hidden) {
    ((void (*)(id, SEL, BOOL))PLXOrigTabBarSetHidden)(self, _cmd, hidden);
    PLXTabRail *rail = objc_getAssociatedObject(self, PLXRailKey);
    if (rail && PLXVerticalBarEdge(self) != 0) rail.hidden = hidden;
}

static BOOL PLXInstallTabBarRail(void) {
    static BOOL installed;
    if (installed) return YES;
    Class tabBarClass = NSClassFromString(@"PMSafeAreaTabBar");
    if (!tabBarClass) return NO;
    installed = YES;
    Method layout = class_getInstanceMethod(tabBarClass, @selector(layoutSubviews));
    if (class_addMethod(tabBarClass, @selector(layoutSubviews), (IMP)PLXTabBarLayoutSubviews, method_getTypeEncoding(layout))) {
        PLXOrigTabBarLayout = method_getImplementation(class_getInstanceMethod([tabBarClass superclass], @selector(layoutSubviews)));
    } else {
        PLXOrigTabBarLayout = method_setImplementation(layout, (IMP)PLXTabBarLayoutSubviews);
    }
    Method setHidden = class_getInstanceMethod(tabBarClass, @selector(setHidden:));
    if (class_addMethod(tabBarClass, @selector(setHidden:), (IMP)PLXTabBarSetHidden, method_getTypeEncoding(setHidden))) {
        PLXOrigTabBarSetHidden = method_getImplementation(class_getInstanceMethod([tabBarClass superclass], @selector(setHidden:)));
    } else {
        PLXOrigTabBarSetHidden = method_setImplementation(setHidden, (IMP)PLXTabBarSetHidden);
    }
    return YES;
}

__attribute__((constructor)) static void PLXInstallTabBarRailAtLaunch(void) {
    if (PLXInstallTabBarRail()) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { PLXInstallTabBarRail(); }];
}
