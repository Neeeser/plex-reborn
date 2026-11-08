// Poster rows scroll behind the Duo's vertical bar.
//
// Plex's hub screens (Home, Trending, libraries) are table views whose cells
// each hold a horizontally scrolling row of posters. Table cells inset their
// content to the safe area, so with the Duo's vertical bar showing every row
// stops 84 pt short of the screen edge and the bar's strip is an empty column.
// Apple's Duo guidance is to let scrolling content and backgrounds run under
// the bar. For tables that hold horizontal rows, the cells now span the full
// width, and each row adds the bar's overlap to its content inset
// (contentInsetAdjustmentBehavior = always) so its last poster can still
// scroll clear of the bar. Tables of plain rows (settings, lists of text) are
// left alone so their text and controls stay inside the safe area.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PlexReborn.h"

static BOOL PLXIsHorizontalRow(UIView *view) {
    if (![view isKindOfClass:UICollectionView.class]) return NO;
    UICollectionViewLayout *layout = ((UICollectionView *)view).collectionViewLayout;
    if ([layout isKindOfClass:UICollectionViewFlowLayout.class]) {
        return ((UICollectionViewFlowLayout *)layout).scrollDirection == UICollectionViewScrollDirectionHorizontal;
    }
    if ([layout isKindOfClass:UICollectionViewCompositionalLayout.class]) {
        return ((UICollectionViewCompositionalLayout *)layout).configuration.scrollDirection == UICollectionViewScrollDirectionHorizontal;
    }
    // Plex's hub rows use their own layout class: judge by shape instead. A row
    // is wider in content than its frame, or no taller than its frame.
    CGSize content = ((UICollectionView *)view).contentSize;
    CGSize size = view.bounds.size;
    return content.width > size.width + 1 || (content.height > 0 && content.height <= size.height + 1);
}

// Horizontal rows within the first few levels of a cell's content view.
static void PLXCollectRows(UIView *view, NSUInteger depth, NSMutableArray<UICollectionView *> *rows) {
    if (PLXIsHorizontalRow(view)) { [rows addObject:(UICollectionView *)view]; return; }
    if (depth == 0) return;
    for (UIView *sub in view.subviews) PLXCollectRows(sub, depth - 1, rows);
}

static const void *PLXOriginalAdjustmentKey = &PLXOriginalAdjustmentKey;
static IMP PLXOrigTableLayout;

// Plex slides the whole screen sideways while its side menu is open, so the
// table's safe area briefly reports most of the screen as covered by the
// vertical bar. The scroll indicator, placed from that safe area, showed up
// in the middle of the screen and stayed there after the menu closed. Its side
// inset is set from the vertical bar's fixed column instead.
static void PLXFixScrollIndicator(UITableView *table, NSInteger edge, BOOL under) {
    if (!under) {
        if (!table.automaticallyAdjustsScrollIndicatorInsets) {
            table.verticalScrollIndicatorInsets = UIEdgeInsetsZero;
            table.automaticallyAdjustsScrollIndicatorInsets = YES;
        }
        return;
    }
    BOOL rightToLeft = table.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL barOnRight = (edge == 2) != rightToLeft;
    UIEdgeInsets safe = table.safeAreaInsets;
    UIEdgeInsets insets = UIEdgeInsetsMake(safe.top, 0, safe.bottom, 0);
    if (barOnRight) insets.right = PLXVerticalBarColumnWidth;
    else insets.left = PLXVerticalBarColumnWidth;
    if (table.automaticallyAdjustsScrollIndicatorInsets) table.automaticallyAdjustsScrollIndicatorInsets = NO;
    if (!UIEdgeInsetsEqualToEdgeInsets(table.verticalScrollIndicatorInsets, insets)) table.verticalScrollIndicatorInsets = insets;
}

static void PLXTableLayoutSubviews(UITableView *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigTableLayout)(self, _cmd);
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = self.window ? self.window.traitCollection.verticalBarEdge : 0;
    if (edge == 0) return;
    NSMutableArray<UICollectionView *> *rows = [NSMutableArray array];
    for (UITableViewCell *cell in self.visibleCells) PLXCollectRows(cell.contentView, 3, rows);
    if (rows.count == 0) return;
    BOOL under = PLXSettingBool(PLXSettingRowsUnderBar);
    if (self.insetsContentViewsToSafeArea == under) self.insetsContentViewsToSafeArea = !under;
    PLXFixScrollIndicator(self, edge, under);
    for (UICollectionView *row in rows) {
        // Remember Plex's own behavior so turning the setting off restores it.
        NSNumber *original = objc_getAssociatedObject(row, PLXOriginalAdjustmentKey);
        if (!original) {
            original = @(row.contentInsetAdjustmentBehavior);
            objc_setAssociatedObject(row, PLXOriginalAdjustmentKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIScrollViewContentInsetAdjustmentBehavior wanted = under ? UIScrollViewContentInsetAdjustmentAlways : original.integerValue;
        if (row.contentInsetAdjustmentBehavior != wanted) row.contentInsetAdjustmentBehavior = wanted;
    }
}

__attribute__((constructor)) static void PLXInstallContentUnderBar(void) {
    Method layout = class_getInstanceMethod(UITableView.class, @selector(layoutSubviews));
    PLXOrigTableLayout = method_setImplementation(layout, (IMP)PLXTableLayoutSubviews);
}
