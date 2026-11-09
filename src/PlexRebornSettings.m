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
NSString *const PLXSettingGlassPlayerControls = @"PlexReborn.glassPlayerControls";
NSString *const PLXSettingLibraryTabs = @"PlexReborn.libraryTabs";
NSString *const PLXSettingHideMoviesAndShows = @"PlexReborn.hideMoviesAndShows";
NSString *const PLXSettingHideRentals = @"PlexReborn.hideRentals";
NSString *const PLXSettingHideDiscover = @"PlexReborn.hideDiscover";
NSString *const PLXSettingHidePlexLiveTV = @"PlexReborn.hidePlexLiveTV";
NSString *const PLXSettingsDidChangeNotification = @"PlexRebornSettingsDidChange";

// Version 0.1.0 had one switch for all of Plex's online content; its value is
// the default for each of the separate switches that replaced it.
static NSString *const PLXLegacyHideOnlineContent = @"PlexReborn.hideOnlineContent";

static const NSUInteger PLXMaxTabs = 5;

static NSArray<NSString *> *PLXHideOnlineKeys(void) {
    return @[PLXSettingHideMoviesAndShows, PLXSettingHideRentals, PLXSettingHideDiscover, PLXSettingHidePlexLiveTV];
}

BOOL PLXSettingBool(NSString *key) {
    static NSDictionary<NSString *, NSNumber *> *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = @{ PLXSettingCustomTabBar: @NO, PLXSettingRowsUnderBar: @YES, PLXSettingBarButtonsInVerticalBar: @YES, PLXSettingClearTitleBar: @YES, PLXSettingDeskReflection: @YES, PLXSettingGlassPlayerControls: @YES };
    });
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    if (!value && [PLXHideOnlineKeys() containsObject:key]) value = [NSUserDefaults.standardUserDefaults objectForKey:PLXLegacyHideOnlineContent];
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

#pragma mark - Settings pages
//
// The Plex Reborn page lists one row per settings page, like iOS Settings.
// Pages other than Tabs are forms: sections of switch, choice and link rows.

@interface PLXRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;          // link rows: SF Symbol on a colored tile
@property (nonatomic, strong) UIColor *tileColor;
@property (nonatomic, copy) UIViewController *(^page)(void); // link rows
@property (nonatomic, copy) NSString *key;             // switch and choice rows
@property (nonatomic, copy) NSArray<NSString *> *options; // choice rows
@property (nonatomic, copy) BOOL (^isOn)(void);        // switch rows with their own value
@property (nonatomic, copy) void (^setOn)(BOOL on);
@end
@implementation PLXRow
+ (instancetype)link:(NSString *)title symbol:(NSString *)symbol color:(UIColor *)color page:(UIViewController *(^)(void))page {
    PLXRow *row = [self new]; row.title = title; row.symbol = symbol; row.tileColor = color; row.page = page; return row;
}
+ (instancetype)toggle:(NSString *)title key:(NSString *)key {
    PLXRow *row = [self new]; row.title = title; row.key = key; return row;
}
+ (instancetype)choice:(NSString *)title key:(NSString *)key options:(NSArray<NSString *> *)options {
    PLXRow *row = [self new]; row.title = title; row.key = key; row.options = options; return row;
}
@end

@interface PLXSection : NSObject
@property (nonatomic, copy) NSString *header, *footer;
@property (nonatomic, copy) NSArray<PLXRow *> *rows;
@end
@implementation PLXSection
+ (instancetype)header:(NSString *)header rows:(NSArray<PLXRow *> *)rows footer:(NSString *)footer {
    PLXSection *s = [self new]; s.header = header; s.rows = rows; s.footer = footer; return s;
}
@end

static UITableViewCell *PLXSwitchCell(NSString *title, BOOL on, id target, SEL action, NSInteger tag) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.textLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *toggle = [UISwitch new];
    toggle.on = on;
    toggle.tag = tag;
    [toggle addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

// A row whose value is picked from a pop-up menu; the stored value is the option's index.
static UITableViewCell *PLXChoiceCell(NSString *title, NSString *key, NSArray<NSString *> *options) {
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

// An SF Symbol in white on a rounded colored square, like iOS Settings.
static UIImage *PLXTileImage(NSString *symbol, UIColor *color) {
    CGFloat side = 29;
    UIImage *glyph = [[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]
        imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:7] fill];
        CGSize g = glyph.size;
        [glyph drawInRect:CGRectMake((side - g.width) / 2, (side - g.height) / 2, g.width, g.height)];
    }];
}

@interface PLXFormViewController : UITableViewController
@property (nonatomic, copy) NSArray<PLXSection *> *(^build)(void);
@property (nonatomic, copy) NSArray<PLXSection *> *sections;
@end

@implementation PLXFormViewController

- (instancetype)initWithTitle:(NSString *)title build:(NSArray<PLXSection *> *(^)(void))build {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { self.title = title; _build = [build copy]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    self.sections = self.build();
    [self.tableView reloadData];
}

- (PLXRow *)rowAt:(NSIndexPath *)indexPath { return self.sections[indexPath.section].rows[indexPath.row]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.sections[section].rows.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section].header; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return self.sections[section].footer; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PLXRow *row = [self rowAt:indexPath];
    if (row.page) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = row.title;
        cell.imageView.image = PLXTileImage(row.symbol, row.tileColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (row.options) return PLXChoiceCell(row.title, row.key, row.options);
    BOOL on = row.isOn ? row.isOn() : PLXSettingBool(row.key);
    NSInteger tag = indexPath.section * 1000 + indexPath.row;
    return PLXSwitchCell(row.title, on, self, @selector(toggled:), tag);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PLXRow *row = [self rowAt:indexPath];
    if (row.page) [self.navigationController pushViewController:row.page() animated:YES];
}

- (void)toggled:(UISwitch *)sender {
    PLXRow *row = self.sections[sender.tag / 1000].rows[sender.tag % 1000];
    if (row.setOn) row.setOn(sender.on);
    else PLXSetSetting(row.key, @(sender.on));
    // Rows can depend on each other ("Hide all"), so redraw the page.
    dispatch_async(dispatch_get_main_queue(), ^{ [self reload]; });
}

@end

#pragma mark Tabs page

typedef NS_ENUM(NSInteger, PLXTabsSection) {
    PLXTabsSectionSwitch,
    PLXTabsSectionChosen,
    PLXTabsSectionAvailable,
    PLXTabsSectionLibrary,
    PLXTabsSectionCount,
};

@interface PLXTabsSettingsViewController : UITableViewController
@property (nonatomic, strong) NSArray<PLXTabEntry *> *available;
@property (nonatomic, strong) NSMutableArray<NSString *> *chosen;
@end

@implementation PLXTabsSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Tabs";
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return PLXTabsSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case PLXTabsSectionSwitch: return 1;
        case PLXTabsSectionChosen: return self.custom ? self.chosen.count : 0;
        case PLXTabsSectionAvailable: return self.custom ? self.unchosen.count : 0;
        case PLXTabsSectionLibrary: return 1;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case PLXTabsSectionChosen: return self.custom ? [NSString stringWithFormat:@"Your tabs (up to %lu)", (unsigned long)PLXMaxTabs] : nil;
        case PLXTabsSectionAvailable: return self.custom ? @"Add a tab" : nil;
        case PLXTabsSectionLibrary: return @"Libraries";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case PLXTabsSectionSwitch:
            return self.custom
                ? @"These tabs replace Plex's tabs at the bottom, or in the vertical bar on iPhone Duo. Side menu entries open the same screen as in the side menu."
                : @"Off: the tab bar shows the tabs of the current screen.";
        case PLXTabsSectionAvailable:
            return self.custom ? @"Side menu entries appear here once the side menu has loaded." : nil;
        case PLXTabsSectionLibrary:
            return @"A library's Recommended, Library and Categories: as one button with a menu, as tabs in the iPhone Duo's vertical bar in place of your tabs, or as Plex's bar along the bottom. Each library opens on the tab you last picked.";
    }
    return nil;
}

- (UITableViewCell *)tabCellForEntry:(PLXTabEntry *)entry {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    // A saved tab that Plex does not offer right now (say, Live TV on an
    // account without it) is skipped in the tab bar; say so here.
    BOOL available = [self.available containsObject:entry];
    cell.textLabel.text = entry.title;
    cell.textLabel.textColor = available ? UIColor.labelColor : UIColor.secondaryLabelColor;
    cell.detailTextLabel.text = !available ? @"Not available right now"
        : [entry.identifier hasPrefix:@"home:"] ? @"Home screen tab" : (entry.subtitle.length ? entry.subtitle : @"Side menu");
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    // Every row gets an icon so the titles line up.
    UIImage *image = entry.image ?: [UIImage systemImageNamed:available ? @"square.dashed" : @"exclamationmark.circle"];
    cell.imageView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.tintColor = available ? UIColor.labelColor : UIColor.secondaryLabelColor;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case PLXTabsSectionSwitch:
            return PLXSwitchCell(@"Choose my own tabs", self.custom, self, @selector(toggleCustom:), 0);
        case PLXTabsSectionChosen:
            return [self tabCellForEntry:[self entryWithID:self.chosen[indexPath.row]]];
        case PLXTabsSectionAvailable:
            return [self tabCellForEntry:self.unchosen[indexPath.row]];
        case PLXTabsSectionLibrary:
            return PLXChoiceCell(@"Library tabs", PLXSettingLibraryTabs, @[@"Menu button", @"Vertical bar tabs", @"Plex's bottom bar"]);
    }
    return [UITableViewCell new];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == PLXTabsSectionChosen || indexPath.section == PLXTabsSectionAvailable;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == PLXTabsSectionChosen) return UITableViewCellEditingStyleDelete;
    if (indexPath.section == PLXTabsSectionAvailable) return UITableViewCellEditingStyleInsert;
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView canEditRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style == UITableViewCellEditingStyleDelete && indexPath.section == PLXTabsSectionChosen) {
        if (self.chosen.count <= 1) return; // keep at least one tab
        [self.chosen removeObjectAtIndex:indexPath.row];
    } else if (style == UITableViewCellEditingStyleInsert && indexPath.section == PLXTabsSectionAvailable) {
        if (self.chosen.count >= PLXMaxTabs) return;
        [self.chosen addObject:self.unchosen[indexPath.row].identifier];
    }
    [self saveChosen];
    [tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == PLXTabsSectionAvailable) {
        [self tableView:tableView commitEditingStyle:UITableViewCellEditingStyleInsert forRowAtIndexPath:indexPath];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == PLXTabsSectionChosen;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    if (to.section < PLXTabsSectionChosen) return [NSIndexPath indexPathForRow:0 inSection:PLXTabsSectionChosen];
    if (to.section > PLXTabsSectionChosen) return [NSIndexPath indexPathForRow:self.chosen.count - 1 inSection:PLXTabsSectionChosen];
    return to;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSString *moved = self.chosen[from.row];
    [self.chosen removeObjectAtIndex:from.row];
    [self.chosen insertObject:moved atIndex:to.row];
    [self saveChosen];
}

- (void)toggleCustom:(UISwitch *)sender {
    if (sender.on && ![NSUserDefaults.standardUserDefaults arrayForKey:PLXSettingTabBarItems]) [self saveChosen];
    PLXSetSetting(PLXSettingCustomTabBar, @(sender.on));
    self.tableView.editing = sender.on;
    [self.tableView reloadData];
}

@end

#pragma mark Pages

static UIViewController *PLXOnlineContentPage(void) {
    return [[PLXFormViewController alloc] initWithTitle:@"Plex Online Content" build:^NSArray<PLXSection *> *{
        PLXRow *all = [PLXRow toggle:@"Hide all of Plex's online content" key:nil];
        all.isOn = ^BOOL {
            for (NSString *key in PLXHideOnlineKeys()) if (!PLXSettingBool(key)) return NO;
            return YES;
        };
        all.setOn = ^(BOOL on) {
            for (NSString *key in PLXHideOnlineKeys()) [NSUserDefaults.standardUserDefaults setObject:@(on) forKey:key];
            [NSNotificationCenter.defaultCenter postNotificationName:PLXSettingsDidChangeNotification object:nil];
        };
        return @[
            [PLXSection header:nil rows:@[all] footer:@"Shows only your own libraries, the libraries shared with you, your Watchlist and your server's Live TV."],
            [PLXSection header:@"Hide" rows:@[
                [PLXRow toggle:@"Movies & Shows" key:PLXSettingHideMoviesAndShows],
                [PLXRow toggle:@"Rentals" key:PLXSettingHideRentals],
                [PLXRow toggle:@"Discover" key:PLXSettingHideDiscover],
                [PLXRow toggle:@"Live TV channels from Plex" key:PLXSettingHidePlexLiveTV],
            ] footer:@"Hidden content leaves the side menu, the More page and Home. Hiding Plex's Live TV channels leaves only your server's channels in the guide."],
        ];
    }];
}

static UIViewController *PLXInterfacePage(void) {
    return [[PLXFormViewController alloc] initWithTitle:@"Interface" build:^NSArray<PLXSection *> *{
        return @[
            [PLXSection header:@"Bars" rows:@[
                [PLXRow toggle:@"Clear title bar that hides while scrolling" key:PLXSettingClearTitleBar],
                [PLXRow toggle:@"Top bar buttons in the vertical bar" key:PLXSettingBarButtonsInVerticalBar],
            ] footer:@"The clear title bar also leaves the title off the first screen of each tab, so content starts at the top. Both apply while the iPhone Duo's vertical bar shows."],
            [PLXSection header:@"Mini Player" rows:@[
                [PLXRow choice:@"Style" key:PLXSettingMiniPlayerStyle options:@[@"Floating card", @"Full-width bar", @"Plex's bar"]],
            ] footer:@"The floating card is a glass capsule above the tab bar, or a card beside the iPhone Duo's vertical bar. The full-width bar applies beside the vertical bar; elsewhere it shows Plex's bar."],
            [PLXSection header:@"Posters" rows:@[
                [PLXRow toggle:@"Posters scroll under the vertical bar" key:PLXSettingRowsUnderBar],
            ] footer:@"Poster rows and the Live TV guide run to the screen edge under the iPhone Duo's vertical bar."],
        ];
    }];
}

static UIViewController *PLXPlayerPage(void) {
    return [[PLXFormViewController alloc] initWithTitle:@"Player" build:^NSArray<PLXSection *> *{
        return @[
            [PLXSection header:@"Controls" rows:@[
                [PLXRow toggle:@"Glass controls" key:PLXSettingGlassPlayerControls],
            ] footer:@"Shows the player's buttons on glass over the video instead of Plex's gray bars."],
            [PLXSection header:@"Desk Posture" rows:@[
                [PLXRow toggle:@"Reflect the video below the fold" key:PLXSettingDeskReflection],
            ] footer:@"With an iPhone Duo half open like a laptop, video plays on the top half and the controls sit on the bottom half over a reflection of the video."],
        ];
    }];
}

static UIViewController *PLXRootPage(void) {
    return [[PLXFormViewController alloc] initWithTitle:@"Plex Reborn" build:^NSArray<PLXSection *> *{
        return @[
            [PLXSection header:@"Features" rows:@[
                [PLXRow link:@"Tabs" symbol:@"square.grid.2x2.fill" color:UIColor.systemOrangeColor page:^UIViewController *{ return [PLXTabsSettingsViewController new]; }],
                [PLXRow link:@"Plex Online Content" symbol:@"globe" color:UIColor.systemBlueColor page:^{ return PLXOnlineContentPage(); }],
                [PLXRow link:@"Interface" symbol:@"rectangle.3.group.fill" color:UIColor.systemPurpleColor page:^{ return PLXInterfacePage(); }],
                [PLXRow link:@"Player" symbol:@"play.rectangle.fill" color:UIColor.systemRedColor page:^{ return PLXPlayerPage(); }],
            ] footer:[NSString stringWithFormat:@"Plex Reborn %s", PLX_VERSION]],
        ];
    }];
}

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
        subtitle.text = @"Tabs, content and layout";
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
    UIViewController *settings = PLXRootPage();
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
