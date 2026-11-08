// Plex Reborn settings: storage, the settings screen, and its entry in Plex's
// own Settings list.
//
// Plex's Settings screen (PMSettingsViewController) is a table. Adding a row
// to it would shift every index Plex's own data source relies on, so the
// "Plex Reborn" entry is the table's header view instead, styled like Plex's rows.
#import "PlexReborn.h"
#import <objc/runtime.h>

#ifndef PLX_VERSION
#define PLX_VERSION "dev"
#endif

NSString *const PLXSettingCustomTabBar = @"PlexReborn.customTabBar";
NSString *const PLXSettingTabBarItems = @"PlexReborn.tabBarItems";
NSString *const PLXSettingRowsUnderBar = @"PlexReborn.rowsUnderBar";
NSString *const PLXSettingMiniPlayerStyle = @"PlexReborn.miniPlayerStyle";
NSString *const PLXSettingBarButtonsInVerticalBar = @"PlexReborn.barButtonsInVerticalBar";
NSString *const PLXSettingClearTitleBar = @"PlexReborn.clearTitleBar";
NSString *const PLXSettingDeskReflection = @"PlexReborn.deskReflection";
NSString *const PLXSettingLibraryTabs = @"PlexReborn.libraryTabs";
NSString *const PLXSettingHideOnlineContent = @"PlexReborn.hideOnlineContent";
NSString *const PLXSettingsDidChangeNotification = @"PlexRebornSettingsDidChange";

static const NSUInteger PLXMaxTabs = 5;

BOOL PLXSettingBool(NSString *key) {
    static NSDictionary<NSString *, NSNumber *> *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = @{ PLXSettingCustomTabBar: @NO, PLXSettingRowsUnderBar: @YES, PLXSettingBarButtonsInVerticalBar: @YES, PLXSettingClearTitleBar: @YES, PLXSettingDeskReflection: @YES };
    });
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return value ? [value boolValue] : defaults[key].boolValue;
}

NSInteger PLXSettingInteger(NSString *key) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

static void PLXSetSetting(NSString *key, id value) {
    [NSUserDefaults.standardUserDefaults setObject:value forKey:key];
    [NSNotificationCenter.defaultCenter postNotificationName:PLXSettingsDidChangeNotification object:nil];
}

@implementation PLXTabEntry
@end

#pragma mark - Settings screen

typedef NS_ENUM(NSInteger, PLXSection) {
    PLXSectionTabBarSwitch,
    PLXSectionChosenTabs,
    PLXSectionAvailableTabs,
    PLXSectionContent,
    PLXSectionLayout,
    PLXSectionAbout,
    PLXSectionCount,
};

@interface PLXSettingsViewController : UITableViewController
@property (nonatomic, strong) NSArray<PLXTabEntry *> *available;
@property (nonatomic, strong) NSMutableArray<NSString *> *chosen;
@end

@implementation PLXSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Plex Reborn";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.allowsSelectionDuringEditing = YES;
    [self reloadModel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadModel];
    [self.tableView reloadData];
}

- (void)reloadModel {
    self.available = PLXAvailableTabEntries();
    NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:PLXSettingTabBarItems];
    if (!saved) {
        // Start from Plex's own Home tabs.
        NSMutableArray *ids = [NSMutableArray array];
        for (PLXTabEntry *e in self.available) if ([e.identifier hasPrefix:@"home:"]) [ids addObject:e.identifier];
        saved = ids;
    }
    self.chosen = [saved mutableCopy];
    self.tableView.editing = PLXSettingBool(PLXSettingCustomTabBar);
}

- (void)saveChosen {
    PLXSetSetting(PLXSettingTabBarItems, [self.chosen copy]);
}

- (PLXTabEntry *)entryWithID:(NSString *)identifier {
    for (PLXTabEntry *e in self.available) if ([e.identifier isEqualToString:identifier]) return e;
    PLXTabEntry *missing = [PLXTabEntry new];
    missing.identifier = identifier;
    NSRange colon = [identifier rangeOfString:@":"];
    missing.title = colon.location == NSNotFound ? identifier : [[identifier substringFromIndex:colon.location + 1] componentsSeparatedByString:@"|"].firstObject;
    return missing;
}

- (NSArray<PLXTabEntry *> *)unchosen {
    NSMutableArray *list = [NSMutableArray array];
    for (PLXTabEntry *e in self.available) if (![self.chosen containsObject:e.identifier]) [list addObject:e];
    return list;
}

- (BOOL)custom { return PLXSettingBool(PLXSettingCustomTabBar); }

#pragma mark Table data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return PLXSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case PLXSectionTabBarSwitch: return 1;
        case PLXSectionChosenTabs: return self.custom ? self.chosen.count : 0;
        case PLXSectionAvailableTabs: return self.custom ? self.unchosen.count : 0;
        case PLXSectionContent: return 1;
        case PLXSectionLayout: return 6;
        case PLXSectionAbout: return 1;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case PLXSectionTabBarSwitch: return @"iPhone Duo tab bar";
        case PLXSectionChosenTabs: return self.custom ? [NSString stringWithFormat:@"Your tabs (up to %lu)", (unsigned long)PLXMaxTabs] : nil;
        case PLXSectionAvailableTabs: return self.custom ? @"Add a tab" : nil;
        case PLXSectionContent: return @"Content";
        case PLXSectionLayout: return @"Layout";
        case PLXSectionAbout: return @"About";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case PLXSectionTabBarSwitch:
            return self.custom
                ? @"These tabs replace the Home screen's tabs in the vertical bar. Side menu entries open the same screen as in the side menu."
                : @"Off: the vertical bar shows the tabs of the current screen.";
        case PLXSectionAvailableTabs:
            return self.custom ? @"Side menu entries appear here once the side menu has loaded." : nil;
        case PLXSectionContent:
            return @"Removes Plex's Movies & Shows, Rentals and Discover from the side menu and Home. Your libraries, Watchlist and Live TV stay.";
        case PLXSectionLayout:
            return @"Applies when the iPhone Duo's vertical bar is showing. Library tabs are a library's Recommended, Library and Categories: as one button with a menu, as tabs in the vertical bar in place of your tabs, or as Plex's bar along the bottom.";
    }
    return nil;
}

- (UITableViewCell *)switchCellTitled:(NSString *)title on:(BOOL)on action:(SEL)action {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.textLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *toggle = [UISwitch new];
    toggle.on = on;
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

// A row whose value is picked from a pop-up menu; the stored value is the option's index.
- (UITableViewCell *)choiceCellTitled:(NSString *)title key:(NSString *)key options:(NSArray<NSString *> *)options {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSInteger current = PLXSettingInteger(key);
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    [options enumerateObjectsUsingBlock:^(NSString *option, NSUInteger i, BOOL *stop) {
        UIAction *action = [UIAction actionWithTitle:option image:nil identifier:nil handler:^(UIAction *a) { PLXSetSetting(key, @(i)); }];
        action.state = (NSInteger)i == current ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }];
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.indicator = UIButtonConfigurationIndicatorPopup;
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.menu = [UIMenu menuWithChildren:actions];
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = YES;
    [button sizeToFit];
    cell.accessoryView = button;
    return cell;
}

- (UITableViewCell *)tabCellForEntry:(PLXTabEntry *)entry {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = entry.title;
    cell.detailTextLabel.text = [entry.identifier hasPrefix:@"home:"] ? @"Home screen tab" : (entry.subtitle.length ? entry.subtitle : @"Side menu");
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.image = [entry.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.tintColor = UIColor.labelColor;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case PLXSectionTabBarSwitch:
            return [self switchCellTitled:@"Choose my own tabs" on:self.custom action:@selector(toggleCustom:)];
        case PLXSectionChosenTabs:
            return [self tabCellForEntry:[self entryWithID:self.chosen[indexPath.row]]];
        case PLXSectionAvailableTabs:
            return [self tabCellForEntry:self.unchosen[indexPath.row]];
        case PLXSectionContent:
            return [self switchCellTitled:@"Hide Plex's online content" on:PLXSettingBool(PLXSettingHideOnlineContent) action:@selector(toggleHideOnline:)];
        case PLXSectionLayout:
            if (indexPath.row == 0) return [self switchCellTitled:@"Top bar buttons in the vertical bar" on:PLXSettingBool(PLXSettingBarButtonsInVerticalBar) action:@selector(toggleBarButtons:)];
            if (indexPath.row == 1) return [self switchCellTitled:@"Clear title bar that hides while scrolling" on:PLXSettingBool(PLXSettingClearTitleBar) action:@selector(toggleClearTitleBar:)];
            if (indexPath.row == 2) return [self choiceCellTitled:@"Library tabs" key:PLXSettingLibraryTabs
                options:@[@"Menu button", @"Vertical bar tabs", @"Plex's bottom bar"]];
            if (indexPath.row == 3) return [self switchCellTitled:@"Posters scroll under the vertical bar" on:PLXSettingBool(PLXSettingRowsUnderBar) action:@selector(toggleRowsUnderBar:)];
            if (indexPath.row == 5) return [self switchCellTitled:@"Reflect the video below the fold in desk posture" on:PLXSettingBool(PLXSettingDeskReflection) action:@selector(toggleDeskReflection:)];
            return [self choiceCellTitled:@"Mini player" key:PLXSettingMiniPlayerStyle
                options:@[@"Floating card", @"Full-width bar", @"Plex's bar"]];
        case PLXSectionAbout: {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
            cell.textLabel.text = @"Version";
            cell.detailTextLabel.text = @PLX_VERSION;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
    }
    return [UITableViewCell new];
}

#pragma mark Editing

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == PLXSectionChosenTabs || indexPath.section == PLXSectionAvailableTabs;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == PLXSectionChosenTabs) return UITableViewCellEditingStyleDelete;
    if (indexPath.section == PLXSectionAvailableTabs) return UITableViewCellEditingStyleInsert;
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView canEditRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style == UITableViewCellEditingStyleDelete && indexPath.section == PLXSectionChosenTabs) {
        if (self.chosen.count <= 1) return; // keep at least one tab
        [self.chosen removeObjectAtIndex:indexPath.row];
    } else if (style == UITableViewCellEditingStyleInsert && indexPath.section == PLXSectionAvailableTabs) {
        if (self.chosen.count >= PLXMaxTabs) return;
        [self.chosen addObject:self.unchosen[indexPath.row].identifier];
    }
    [self saveChosen];
    [tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == PLXSectionAvailableTabs) {
        [self tableView:tableView commitEditingStyle:UITableViewCellEditingStyleInsert forRowAtIndexPath:indexPath];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == PLXSectionChosenTabs;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    if (to.section < PLXSectionChosenTabs) return [NSIndexPath indexPathForRow:0 inSection:PLXSectionChosenTabs];
    if (to.section > PLXSectionChosenTabs) return [NSIndexPath indexPathForRow:self.chosen.count - 1 inSection:PLXSectionChosenTabs];
    return to;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSString *moved = self.chosen[from.row];
    [self.chosen removeObjectAtIndex:from.row];
    [self.chosen insertObject:moved atIndex:to.row];
    [self saveChosen];
}

#pragma mark Switches

- (void)toggleCustom:(UISwitch *)sender {
    if (sender.on && ![NSUserDefaults.standardUserDefaults arrayForKey:PLXSettingTabBarItems]) [self saveChosen];
    PLXSetSetting(PLXSettingCustomTabBar, @(sender.on));
    self.tableView.editing = sender.on;
    [self.tableView reloadData];
}

- (void)toggleRowsUnderBar:(UISwitch *)sender { PLXSetSetting(PLXSettingRowsUnderBar, @(sender.on)); }
- (void)toggleDeskReflection:(UISwitch *)sender { PLXSetSetting(PLXSettingDeskReflection, @(sender.on)); }
- (void)toggleClearTitleBar:(UISwitch *)sender { PLXSetSetting(PLXSettingClearTitleBar, @(sender.on)); }
- (void)toggleBarButtons:(UISwitch *)sender { PLXSetSetting(PLXSettingBarButtonsInVerticalBar, @(sender.on)); }
- (void)toggleHideOnline:(UISwitch *)sender { PLXSetSetting(PLXSettingHideOnlineContent, @(sender.on)); }

@end

#pragma mark - Entry in Plex's Settings

@interface PLXSettingsEntryView : UIControl
@property (nonatomic, weak) UIViewController *owner;
@end

@implementation PLXSettingsEntryView

- (instancetype)initWithOwner:(UIViewController *)owner {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 320, 76)])) {
        _owner = owner;
        UIView *row = [UIView new];
        row.userInteractionEnabled = NO;
        row.backgroundColor = [UIColor colorWithRed:0.13 green:0.14 blue:0.16 alpha:1];
        row.layer.cornerRadius = 12;
        row.layer.cornerCurve = kCACornerCurveContinuous;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:row];

        UILabel *title = [UILabel new];
        title.text = @"Plex Reborn";
        title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        title.textColor = UIColor.whiteColor;
        UILabel *subtitle = [UILabel new];
        subtitle.text = @"iPhone Duo tab bar and layout";
        subtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.6];
        UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]];
        labels.axis = UILayoutConstraintAxisVertical;
        labels.spacing = 2;
        labels.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:labels];

        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        chevron.tintColor = [UIColor colorWithWhite:1 alpha:0.6];
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:chevron];

        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
            [labels.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
            [labels.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
            [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];
        [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
        self.accessibilityLabel = @"Plex Reborn settings";
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)open {
    UIViewController *owner = self.owner;
    PLXSettingsViewController *settings = [PLXSettingsViewController new];
    if (owner.navigationController) [owner.navigationController pushViewController:settings animated:YES];
    else [owner presentViewController:[[UINavigationController alloc] initWithRootViewController:settings] animated:YES completion:nil];
}

@end

static UITableView *PLXFindTable(UIView *view) {
    if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    for (UIView *sub in view.subviews) { UITableView *t = PLXFindTable(sub); if (t) return t; }
    return nil;
}

static IMP PLXOrigSettingsViewWillAppear;

// Added before the screen appears; adding it once the screen had appeared
// pushed Plex's first section down while it was already on screen.
static void PLXSettingsViewWillAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))PLXOrigSettingsViewWillAppear)(self, _cmd, animated);
    UITableView *table = PLXFindTable(self.view);
    if (!table || [table.tableHeaderView isKindOfClass:PLXSettingsEntryView.class]) return;
    PLXSettingsEntryView *entry = [[PLXSettingsEntryView alloc] initWithOwner:self];
    CGFloat width = CGRectGetWidth(table.bounds) ?: CGRectGetWidth(self.view.bounds);
    entry.frame = CGRectMake(0, 0, width, 76);
    table.tableHeaderView = entry;
}

__attribute__((constructor)) static void PLXInstallSettingsEntry(void) {
    void (^install)(void) = ^{
        static BOOL installed;
        Class settings = NSClassFromString(@"PMSettingsViewController");
        if (installed || !settings) return;
        installed = YES;
        Method m = class_getInstanceMethod(settings, @selector(viewWillAppear:));
        if (class_addMethod(settings, @selector(viewWillAppear:), (IMP)PLXSettingsViewWillAppear, method_getTypeEncoding(m))) {
            PLXOrigSettingsViewWillAppear = method_getImplementation(class_getInstanceMethod([settings superclass], @selector(viewWillAppear:)));
        } else {
            PLXOrigSettingsViewWillAppear = method_setImplementation(m, (IMP)PLXSettingsViewWillAppear);
        }
    };
    install();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { install(); }];
}
