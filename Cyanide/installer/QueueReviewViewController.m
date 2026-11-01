//
//  QueueReviewViewController.m
//  Cyanide
//

#import "QueueReviewViewController.h"
#import "CYIconBadge.h"
#import "PackageQueue.h"
#import "PackageCatalog.h"
#import "InstallProgressViewController.h"
#import "../LogTextView.h"
#import "../SettingsViewController.h"

typedef NS_ENUM(NSInteger, QueueReviewSection) {
    QueueReviewSectionInstall = 0,
    QueueReviewSectionUninstall,
    QueueReviewSectionReApply,
    QueueReviewSectionCount,
};

@interface QueueReviewViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

static BOOL QueuePackageIsHideHomeBar(Package *pkg)
{
    if (pkg.kind == PackageInstallKindHideHomeBar) return YES;
    return pkg.kind == PackageInstallKindRepoTweak &&
           [pkg.repoTweakID isEqualToString:@"lightsaber.hide-homebar"];
}

@implementation QueueReviewViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Queue";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    UIView *footer = [self buildFooter];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:footer];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"没有待处理的变更\n请从「软件包」标签页把软件包加入队列";
    self.emptyLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    self.emptyLabel.textColor = UIColor.tertiaryLabelColor;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    [self.view addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor   constraintEqualToAnchor:footer.topAnchor],

        [footer.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [footer.bottomAnchor   constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor  constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24.0],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24.0],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueChanged:)
                                                 name:PackageQueueDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshUI];
}

- (UIView *)buildFooter
{
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UIButtonConfiguration *confirmCfg = [UIButtonConfiguration filledButtonConfiguration];
    confirmCfg.title = @"Confirm";
    confirmCfg.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    confirmCfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        return attrs;
    };
    self.confirmButton = [UIButton buttonWithConfiguration:confirmCfg primaryAction:[UIAction actionWithHandler:^(UIAction *_) {
        [self didTapConfirm];
    }]];
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.confirmButton];

    UIButtonConfiguration *clearCfg = [UIButtonConfiguration plainButtonConfiguration];
    clearCfg.title = @"清空队列";
    clearCfg.baseForegroundColor = UIColor.systemRedColor;
    clearCfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *incoming) {
        NSMutableDictionary *attrs = [incoming mutableCopy];
        attrs[NSFontAttributeName] = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
        return attrs;
    };
    self.clearButton = [UIButton buttonWithConfiguration:clearCfg primaryAction:[UIAction actionWithHandler:^(UIAction *_) {
        [self didTapClear];
    }]];
    self.clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.clearButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.confirmButton.topAnchor      constraintEqualToAnchor:container.topAnchor constant:8.0],
        [self.confirmButton.leadingAnchor  constraintEqualToAnchor:container.leadingAnchor constant:16.0],
        [self.confirmButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
        [self.confirmButton.heightAnchor   constraintEqualToConstant:50.0],

        [self.clearButton.topAnchor        constraintEqualToAnchor:self.confirmButton.bottomAnchor constant:2.0],
        [self.clearButton.centerXAnchor    constraintEqualToAnchor:container.centerXAnchor],
        [self.clearButton.bottomAnchor     constraintEqualToAnchor:container.bottomAnchor constant:-8.0],
        // A small text button right above the home indicator: keep a full
        // 44 pt touch target (it was text-high and easy to miss).
        [self.clearButton.heightAnchor     constraintGreaterThanOrEqualToConstant:44.0],
        [self.clearButton.widthAnchor      constraintGreaterThanOrEqualToConstant:160.0],
    ]];
    return container;
}

- (void)refreshUI
{
    [self.tableView reloadData];
    [self updateHomeBarWarningHeader];
    NSInteger count = [PackageQueue sharedQueue].pendingCount;
    self.emptyLabel.hidden = (count > 0);
    self.tableView.hidden = (count == 0);
    self.confirmButton.enabled = (count > 0);
    self.clearButton.enabled = (count > 0);

    NSString *confirmTitle;
    if (count == 1) {
        confirmTitle = @"确认 1 项变更";
    } else if (count > 1) {
        confirmTitle = [NSString stringWithFormat:@"确认 %ld 项变更", (long)count];
    } else {
        confirmTitle = @"Confirm";
    }
    UIButtonConfiguration *cfg = self.confirmButton.configuration;
    cfg.title = confirmTitle;
    self.confirmButton.configuration = cfg;
}

- (UIView *)homeBarWarningHeaderView
{
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0.0) width = self.view.bounds.size.width;
    if (width <= 0.0) width = UIScreen.mainScreen.bounds.size.width;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 1.0)];
    container.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor.systemOrangeColor colorWithAlphaComponent:0.14];
    card.layer.cornerRadius = 16.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor.systemOrangeColor colorWithAlphaComponent:0.28].CGColor;
    [container addSubview:card];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.systemOrangeColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:icon];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"「隐藏主屏横条」必须单独运行";
    title.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    title.textColor = UIColor.labelColor;
    [card addSubview:title];

    UILabel *body = [[UILabel alloc] init];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.text = @"它会修改系统的 Home 指示条素材，之后需要重启 SpringBoard。请只确认「隐藏主屏横条」，重启后再把其他插件加入队列。";
    body.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    body.textColor = UIColor.secondaryLabelColor;
    body.numberOfLines = 0;
    [card addSubview:body];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:container.topAnchor constant:12.0],
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],

        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [icon.widthAnchor constraintEqualToConstant:24.0],
        [icon.heightAnchor constraintEqualToConstant:24.0],

        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:12.0],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10.0],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],

        [body.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],
        [body.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [body.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12.0],
    ]];

    CGSize size = [container systemLayoutSizeFittingSize:CGSizeMake(width, 0.0)
                           withHorizontalFittingPriority:UILayoutPriorityRequired
                                 verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    container.frame = CGRectMake(0.0, 0.0, width, ceil(size.height));
    return container;
}

- (void)updateHomeBarWarningHeader
{
    if (![self queueIncludesHideHomeBar]) {
        self.tableView.tableHeaderView = nil;
        return;
    }
    self.tableView.tableHeaderView = [self homeBarWarningHeaderView];
}

- (void)queueChanged:(NSNotification *)note
{
    [self refreshUI];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return QueueReviewSectionCount;
}

- (NSArray<Package *> *)reApplyPackages
{
    if ([self queueIncludesHideHomeBar]) return @[];

    PackageQueue *q = [PackageQueue sharedQueue];
    NSMutableArray<Package *> *out = [NSMutableArray array];
    for (Package *p in [PackageCatalog allPackages]) {
        if (!p.isInstalled) continue;
        if ([q intentForPackage:p] != PackageQueueIntentNone) continue;
        [out addObject:p];
    }

    BOOL hasRepoTweakUsingQL = NO;
    for (Package *p in q.queuedInstalls) {
        if (p.kind == PackageInstallKindRepoTweak && p.repoTweakUsesQuickLoader) {
            hasRepoTweakUsingQL = YES;
            break;
        }
    }
    if (!hasRepoTweakUsingQL) {
        for (Package *p in out) {
            if (p.kind == PackageInstallKindRepoTweak && p.repoTweakUsesQuickLoader) {
                hasRepoTweakUsingQL = YES;
                break;
            }
        }
    }
    if (hasRepoTweakUsingQL) {
        NSMutableArray<Package *> *filtered = [NSMutableArray arrayWithCapacity:out.count];
        for (Package *p in out) {
            if ([p.enabledKey isEqualToString:kSettingsQuickLoaderEnabled]) continue;
            [filtered addObject:p];
        }
        return filtered;
    }
    return out;
}

- (NSArray<Package *> *)packagesForSection:(NSInteger)section
{
    PackageQueue *q = [PackageQueue sharedQueue];
    switch ((QueueReviewSection)section) {
        case QueueReviewSectionInstall:   return q.queuedInstalls;
        case QueueReviewSectionUninstall: return q.queuedUninstalls;
        case QueueReviewSectionReApply:   return [self reApplyPackages];
        case QueueReviewSectionCount:     return @[];
    }
    return @[];
}

- (BOOL)queueIncludesHideHomeBar
{
    for (Package *pkg in [PackageQueue sharedQueue].queuedInstalls) {
        if (QueuePackageIsHideHomeBar(pkg)) return YES;
    }
    for (Package *pkg in [PackageQueue sharedQueue].queuedUninstalls) {
        if (QueuePackageIsHideHomeBar(pkg)) return YES;
    }
    return NO;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)[self packagesForSection:section].count;
}

- (NSString *)sectionLabel:(NSInteger)section
{
    NSArray<Package *> *list = [self packagesForSection:section];
    if (list.count == 0) return nil;
    PackageInstallKind commonKind = list.firstObject.kind;
    BOOL allSameKind = YES;
    for (Package *pkg in list) {
        if (pkg.kind != commonKind) { allSameKind = NO; break; }
    }
    NSString *label;
    switch ((QueueReviewSection)section) {
        case QueueReviewSectionInstall:
            if (allSameKind && commonKind == PackageInstallKindNanoRegistry) label = @"Apply";
            else if (allSameKind && commonKind == PackageInstallKindCallRecordingSound) label = @"Silence";
            else if (allSameKind && commonKind == PackageInstallKindHideHomeBar) label = @"Hide";
            else if (allSameKind && commonKind == PackageInstallKindRepoTweak) label = @"Install";
            else label = @"Activate";
            break;
        case QueueReviewSectionUninstall:
            if (allSameKind && commonKind == PackageInstallKindNanoRegistry) label = @"Remove";
            else if (allSameKind && commonKind == PackageInstallKindCallRecordingSound) label = @"Restore";
            else if (allSameKind && commonKind == PackageInstallKindHideHomeBar) label = @"Restore";
            else if (allSameKind && commonKind == PackageInstallKindRepoTweak) label = @"Remove";
            else label = @"Deactivate";
            break;
        case QueueReviewSectionReApply: label = @"已生效"; break;
        default: return nil;
    }
    return [NSString stringWithFormat:@"%@  ·  %ld", label, (long)list.count];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSString *label = [self sectionLabel:section];
    return label ? CYSectionHeaderView(label) : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return [self sectionLabel:section] ? 46.0 : 0.0;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    switch ((QueueReviewSection)section) {
        case QueueReviewSectionInstall:
            if (![self queueIncludesHideHomeBar]) return nil;
            return @"「隐藏主屏横条」必须单独运行，因为它会修改系统的 Home 指示条素材，之后需要重启 SpringBoard。请先单独运行它，重启之后再应用其他插件。";
        case QueueReviewSectionReApply:
            if ([self reApplyPackages].count == 0) return nil;
            return @"这些已经安装，并不是新的待处理变更。确认后会重新运行利用链，让依赖 RemoteCall 的插件在强制退出后恢复。想阻止某一项运行，请到「软件包」标签页将其停用，或使用 设置 → 快捷操作 中的「重置全部软件包」。";
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"QueueRow"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"QueueRow"];
    }
    NSArray<Package *> *packages = [self packagesForSection:indexPath.section];
    if (indexPath.row >= (NSInteger)packages.count) {
        cell.textLabel.text = @"已不再待处理";
        cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.text = @"该队列条目已被应用或清除。";
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
        cell.imageView.image = [UIImage systemImageNamed:@"checkmark.circle"];
        cell.imageView.tintColor = UIColor.tertiaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    Package *pkg = packages[indexPath.row];
    BOOL isQuickLoader = (pkg.kind != PackageInstallKindRepoTweak &&
                          [pkg.enabledKey isEqualToString:kSettingsQuickLoaderEnabled]);
    if (isQuickLoader) {
        NSString *scriptName = [[NSUserDefaults standardUserDefaults] stringForKey:@"QuickLoaderSourceScriptName"];
        cell.textLabel.text = scriptName.length ? [NSString stringWithFormat:@"QuickLoader：%@", scriptName] : pkg.name;
    } else {
        cell.textLabel.text = pkg.name;
    }
    cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];

    QueueReviewSection s = (QueueReviewSection)indexPath.section;
    switch (s) {
        case QueueReviewSectionInstall:
            switch (pkg.kind) {
                case PackageInstallKindNanoRegistry:
                    cell.detailTextLabel.text = @"待应用覆盖项";
                    cell.detailTextLabel.textColor = self.view.tintColor;
                    break;
                case PackageInstallKindCallRecordingSound:
                    cell.detailTextLabel.text = @"待静音提示音";
                    cell.detailTextLabel.textColor = UIColor.systemOrangeColor;
                    break;
                case PackageInstallKindHideHomeBar:
                    cell.detailTextLabel.text = @"需单独运行；需要重启 SpringBoard";
                    cell.detailTextLabel.textColor = UIColor.systemOrangeColor;
                    break;
                case PackageInstallKindRepoTweak:
                    cell.detailTextLabel.text = @"待安装";
                    cell.detailTextLabel.textColor = UIColor.systemGreenColor;
                    break;
                default:
                    cell.detailTextLabel.text = @"待启用";
                    cell.detailTextLabel.textColor = UIColor.systemGreenColor;
                    break;
            }
            break;
        case QueueReviewSectionUninstall:
            switch (pkg.kind) {
                case PackageInstallKindNanoRegistry:
                    cell.detailTextLabel.text = @"待移除覆盖项";
                    cell.detailTextLabel.textColor = UIColor.systemRedColor;
                    break;
                case PackageInstallKindCallRecordingSound:
                    cell.detailTextLabel.text = @"待恢复提示音";
                    cell.detailTextLabel.textColor = UIColor.systemGreenColor;
                    break;
                case PackageInstallKindHideHomeBar:
                    cell.detailTextLabel.text = @"待恢复重启设置";
                    cell.detailTextLabel.textColor = UIColor.systemGreenColor;
                    break;
                case PackageInstallKindRepoTweak:
                    cell.detailTextLabel.text = @"待移除";
                    cell.detailTextLabel.textColor = UIColor.systemRedColor;
                    break;
                default:
                    cell.detailTextLabel.text = @"待停用";
                    cell.detailTextLabel.textColor = UIColor.systemRedColor;
                    break;
            }
            break;
        case QueueReviewSectionReApply:
            cell.detailTextLabel.text =
                [pkg.enabledKey isEqualToString:kSettingsSBCEnabled]
                    ? @"已启用；将被应用"
                    : @"已生效；将刷新";
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            break;
        default:
            cell.detailTextLabel.text = nil;
            break;
    }
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    UIColor *queueIconColor = (s == QueueReviewSectionReApply) ? UIColor.tertiaryLabelColor : CYSpectrumColor((NSUInteger)indexPath.row);
    cell.imageView.image = CYIconBadgeImage(pkg.symbolName, queueIconColor, 32.0);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Swipe-to-remove only applies to the pending queue rows. "Will Re-Apply"
    // is informational — to drop one, the user uninstalls it from the
    // Packages tab or runs Reset All Packages.
    QueueReviewSection s = (QueueReviewSection)indexPath.section;
    if (s != QueueReviewSectionInstall && s != QueueReviewSectionUninstall) return nil;

    NSArray<Package *> *packages = [self packagesForSection:indexPath.section];
    if (indexPath.row >= (NSInteger)packages.count) return nil;

    Package *pkg = packages[indexPath.row];
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:@"Remove"
                                                                       handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [[PackageQueue sharedQueue] removePackage:pkg];
        completionHandler(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

#pragma mark - Actions

- (void)didTapConfirm
{
    if ([PackageQueue sharedQueue].pendingCount == 0) return;
    NSInteger count = [PackageQueue sharedQueue].pendingCount;
    BOOL includesHideHomeBar = NO;
    for (Package *pkg in [PackageQueue sharedQueue].queuedInstalls) {
        if (QueuePackageIsHideHomeBar(pkg)) {
            includesHideHomeBar = YES;
            break;
        }
    }
    if (!includesHideHomeBar) {
        for (Package *pkg in [PackageQueue sharedQueue].queuedUninstalls) {
            if (QueuePackageIsHideHomeBar(pkg)) {
                includesHideHomeBar = YES;
                break;
            }
        }
    }
    if (includesHideHomeBar && count > 1) {
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"单独运行「隐藏主屏横条」"
                             message:@"「隐藏主屏横条」会修改系统的 Home 指示条素材，应用后需要重启 SpringBoard。请先移除其他待处理变更，单独运行「隐藏主屏横条」，重启后再应用其他插件。"
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    // isCommitting covers the commit work; settings_run_in_flight covers the
    // run that commit handed off to (the queue no longer owns that phase).
    if ([PackageQueue sharedQueue].isCommitting || settings_run_in_flight()) {
        [self presentInstallStillRunningAlert];
        return;
    }

    InstallProgressViewController *vc = [[InstallProgressViewController alloc] init];
    vc.promptsForHideHomeBarRespring = includesHideHomeBar;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationAutomatic;
    [self presentViewController:nav animated:YES completion:^{
        log_user("[INSTALLER] ── Applying %ld pending change(s) ──\n", (long)count);
        if (![[PackageQueue sharedQueue] commit]) {
            // Lost a race with another commit: don't leave a progress
            // screen spinning for a run it isn't attached to.
            [nav dismissViewControllerAnimated:YES completion:^{
                [self presentInstallStillRunningAlert];
            }];
        }
    }];
}

- (void)presentInstallStillRunningAlert
{
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"安装进行中"
                                                                message:@"仍有安装正在进行。"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)didTapClear
{
    if ([PackageQueue sharedQueue].pendingCount == 0) return;
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"清空队列？"
                                                                message:@"放弃所有待处理的启用 / 停用变更。"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [[PackageQueue sharedQueue] clear];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
