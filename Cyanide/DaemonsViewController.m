//
//  DaemonsViewController.m
//  Cyanide
//

#import "DaemonsViewController.h"
#import "SettingsViewController.h"
#import "tweaks/daemon_catalog.h"
#import "kexploit/persistence.h"
#import "installer/MainTabBarController.h"

// The pending-changes popup bar is hosted by the tab bar controller above
// pushed content; hide it while this screen is on top, as the Process Viewer
// and File Browser do. Each screen re-asserts it on appear, so a push between
// screens that all hide it keeps it hidden.
static void daemons_suppress_popup_bar(UIViewController *vc, BOOL suppressed)
{
    UITabBarController *tbc = vc.tabBarController;
    if ([tbc isKindOfClass:MainTabBarController.class])
        [(MainTabBarController *)tbc setPopupBarSuppressed:suppressed];
}

// Boot session in which the last change was saved: until the next restart
// the screen reminds the user that changes are pending.
static NSString * const kDaemonsChangedBootKey = @"DaemonsChangedBootUUID";

// The catalog version whose brick warning the user acknowledged. Bump
// kDaemonsWarningVersion when the list gets riskier, to warn again.
static NSString * const kDaemonsWarningAcceptedKey = @"DaemonsWarningAcceptedVersion";
static const NSInteger kDaemonsWarningVersion = 1;
// Shows the advanced groups (services other parts of iOS rely on).
static NSString * const kDaemonsShowAdvancedKey = @"DaemonsShowAdvanced";

static BOOL daemons_restart_pending(void)
{
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:kDaemonsChangedBootKey];
    NSString *boot = krw_persistence_current_boot_uuid();
    return saved.length && boot.length && [saved isEqualToString:boot];
}

// Labels changed during the current boot: for them, a running process is
// expected until the restart; for the others, a disabled daemon that runs
// means the disable didn't take effect.
static NSString * const kDaemonsChangedLabelsKey = @"DaemonsChangedLabels";   // @{ boot, labels }

static NSSet<NSString *> *daemons_changed_this_boot(void)
{
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:kDaemonsChangedLabelsKey];
    NSString *boot = krw_persistence_current_boot_uuid();
    if (!boot.length || ![d[@"boot"] isEqual:boot] || ![d[@"labels"] isKindOfClass:NSArray.class]) return [NSSet set];
    return [NSSet setWithArray:d[@"labels"]];
}

static void daemons_note_change(NSArray<NSString *> *labels)
{
    NSString *boot = krw_persistence_current_boot_uuid();
    if (!boot.length) return;
    [NSUserDefaults.standardUserDefaults setObject:boot forKey:kDaemonsChangedBootKey];
    NSMutableSet *all = [daemons_changed_this_boot() mutableCopy];
    [all addObjectsFromArray:labels];
    [NSUserDefaults.standardUserDefaults setObject:@{ @"boot": boot, @"labels": all.allObjects }
                                            forKey:kDaemonsChangedLabelsKey];
}

static void daemons_invalidate_snapshot(NSDictionary * __strong *disabled,
                                         NSDictionary * __strong *running,
                                         NSMutableDictionary *staged,
                                         NSString * __strong *status,
                                         NSString *message)
{
    *disabled = nil;
    *running = nil;
    [staged removeAllObjects];
    *status = message.length ? message : @"无法读取已禁用守护进程的列表。请查看日志。";
}

@class DaemonGroupViewController;

@interface DaemonsViewController ()
@property (nonatomic, copy) NSDictionary *disabled;   // nil until loaded
@property (nonatomic, copy) NSDictionary *running;    // label -> @{ name, pid? }; nil if unknown
// Switch changes not saved yet: label -> @YES (disable) / @NO (enable), only
// where that differs from disabled.plist. Written on Save.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *staged;
@property (nonatomic, copy) NSString *status;          // shown while not loaded / on error
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL snapshotValid;
- (void)setLabels:(NSArray<NSString *> *)labels disabled:(BOOL)disable from:(UIViewController *)presenter;
- (BOOL)isLabelDisabled:(NSString *)label;
- (BOOL)willBeDisabled:(NSString *)label;
- (BOOL)isLabelMissing:(NSString *)label;
- (BOOL)warningAccepted;
- (NSString *)statusForLabel:(NSString *)label warning:(BOOL *)warning;
@end

#pragma mark - One group

@interface DaemonGroupViewController : UITableViewController
@property (nonatomic, strong) CYDaemonGroup *group;
@property (nonatomic, weak) DaemonsViewController *owner;
@end

@implementation DaemonGroupViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.group.title;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    daemons_suppress_popup_bar(self, YES);
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    daemons_suppress_popup_bar(self, NO);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.group.labels.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSString *s = self.group.summary;
    if (self.group.caution) s = [s stringByAppendingFormat:@"\n\n⚠️ %@", self.group.caution];
    return [s stringByAppendingString:@"\n\n「已开启」表示该守护进程可以运行。改动会在你点按「保存」时写入，并在重启后生效。 "
                                      @"大多数守护进程只在有需要时才运行，所以「未运行」并不等于已禁用。 "
                                      @"下拉列表可以刷新。"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"label"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"label"];
    NSString *label = self.group.labels[(NSUInteger)indexPath.row];
    UIListContentConfiguration *c = [UIListContentConfiguration subtitleCellConfiguration];
    c.text = label;
    c.textProperties.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    c.textProperties.adjustsFontSizeToFitWidth = YES;
    c.textProperties.minimumScaleFactor = 0.7;
    c.textProperties.numberOfLines = 1;
    BOOL warning = NO;
    c.secondaryText = [self.owner statusForLabel:label warning:&warning];
    c.secondaryTextProperties.color = warning ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
    c.secondaryTextProperties.numberOfLines = 0;
    cell.contentConfiguration = c;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [UISwitch new];
    sw.on = ![self.owner willBeDisabled:label];
    sw.enabled = self.owner.snapshotValid && self.owner.disabled && !self.owner.busy &&
                 !([self.owner isLabelMissing:label] && ![self.owner isLabelDisabled:label]);
    __weak typeof(self) weakSelf = self;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) {
        typeof(self) me = weakSelf;
        BOOL on = ((UISwitch *)a.sender).isOn;
        [me.owner setLabels:@[ label ] disabled:!on from:me];
    }] forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

@end

#pragma mark - All groups

@implementation DaemonsViewController

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"守护进程管理";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.staged = [NSMutableDictionary dictionary];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                      target:self action:@selector(confirmSave)];
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(pullToRefresh) forControlEvents:UIControlEventValueChanged];
    self.status = @"正在读取已禁用的守护进程…";
    [self loadAllowingFullExploit:NO];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    daemons_suppress_popup_bar(self, YES);
    [self.tableView reloadData];   // a group screen may have changed something
    [self updateInteractivePopGesture];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    daemons_suppress_popup_bar(self, NO);
    // The recognizer belongs to the shared navigation controller (and may be
    // used by a pushed group screen): never leave it disabled after this VC.
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
}

// Unsaved daemon changes have no confirmation on the edge-swipe path; the
// Discard/Back substitution only covers the bar button. Disable the shared
// interactive pop only while this controller is the visible one; a pushed
// group screen keeps its own swipe-back (which returns here, changes intact).
- (void)updateInteractivePopGesture
{
    if (self.navigationController.topViewController != self) return;
    UIGestureRecognizer *pop = self.navigationController.interactivePopGestureRecognizer;
    if (pop) pop.enabled = self.staged.count == 0;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self showWarningIfNeeded];
}

// Once, before anything can be changed: a daemon entry applies at every boot,
// and one that stops iOS from booting can't be undone from Cyanide.
- (void)showWarningIfNeeded
{
    if (self.warningAccepted) return;
    if (self.presentedViewController) return;
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"禁用守护进程可能让设备变砖"
                         message:@"关闭系统守护进程，会改变 iOS 在每次开机时的启动方式。此处列出的服务 "
                                 @"被广泛关闭且没有出现问题，但这并不能保证适用于所有 iOS 版本与设备。\n\n"
                                 @"如果 iOS 无法完成启动，Cyanide 也无法撤销这一改动。只有恢复设备才能修复：它会 "
                                 @"抹除设备（除非你有备份），并安装最新的 iOS，而 Cyanide "
                                 @"很可能不支持该版本。\n\n"
                                 @"请先备份，每次只改一项，重启确认无误后再改下一项。"
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"我已了解" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [NSUserDefaults.standardUserDefaults setInteger:kDaemonsWarningVersion forKey:kDaemonsWarningAcceptedKey];
        [weakSelf refreshUI];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (BOOL)warningAccepted
{
    return [NSUserDefaults.standardUserDefaults integerForKey:kDaemonsWarningAcceptedKey] >= kDaemonsWarningVersion;
}

// Not a launchd job on this iOS version (only known when the job cache was read).
- (BOOL)isLabelMissing:(NSString *)label
{
    return [self.running[label][@"missing"] boolValue];
}

- (void)pullToRefresh
{
    [self.refreshControl endRefreshing];
    [self loadAllowingFullExploit:NO];
}

- (BOOL)isLabelDisabled:(NSString *)label
{
    return [self.disabled[label] boolValue];
}

// What the switch shows: the saved state, or the unsaved change.
- (BOOL)willBeDisabled:(NSString *)label
{
    NSNumber *v = self.staged[label];
    return v != nil ? v.boolValue : [self isLabelDisabled:label];
}

// "tipsd · Running · PID 412", plus what to expect: a daemon disabled in an
// earlier boot that still runs means the disable didn't take effect.
- (NSString *)statusForLabel:(NSString *)label warning:(BOOL *)warning
{
    *warning = NO;
    NSString *status = [self runningStatusForLabel:label warning:warning];
    NSNumber *v = self.staged[label];
    if (v != nil) status = [status stringByAppendingString:v.boolValue ? @" · 保存后禁用" : @" · 保存后启用"];
    return status;
}

- (NSString *)runningStatusForLabel:(NSString *)label warning:(BOOL *)warning
{
    NSDictionary *info = self.running[label];
    NSString *name = info[@"name"] ?: daemon_catalog_executable_guess(label);
    if (!self.running) return [name stringByAppendingString:@" · 状态未知"];
    if (daemon_catalog_is_legacy_label(label))
        return [name stringByAppendingString:@" · 旧版禁用记录；未检查作业是否存在"];
    if ([info[@"missing"] boolValue]) return [name stringByAppendingString:@" · 此 iOS 版本中不存在该作业"];
    if ([info[@"unknown"] boolValue]) return [name stringByAppendingString:@" · 状态未知"];
    NSNumber *pid = info[@"pid"];
    NSNumber *shared = info[@"shared"];
    BOOL off = [self isLabelDisabled:label];
    // One process for several jobs: which job runs it is unknown.
    if (shared != nil)
        return pid != nil ? [NSString stringWithFormat:@"%@ · 运行中 · PID %@ · 由 %@ 个作业共用", name, pid, shared]
                          : [NSString stringWithFormat:@"%@ · 未运行 · 由 %@ 个作业共用", name, shared];
    BOOL changed = [daemons_changed_this_boot() containsObject:label];
    if (pid != nil && off && changed)
        return [NSString stringWithFormat:@"%@ · 运行中 · PID %@ · 重启后停止", name, pid];
    if (pid != nil && off) {
        *warning = YES;
        return [NSString stringWithFormat:@"%@ · 运行中 · PID %@ · 已禁用但仍在运行", name, pid];
    }
    if (pid != nil) return [NSString stringWithFormat:@"%@ · 运行中 · PID %@", name, pid];
    if (off) return [name stringByAppendingString:@" · 未运行"];
    if (changed) return [name stringByAppendingString:@" · 未运行 · 重启后可再次启动"];
    return [name stringByAppendingString:@" · 未运行（需要时启动）"];
}

- (void)refreshUI
{
    BOOL dirty = self.staged.count > 0;
    self.navigationItem.rightBarButtonItem.enabled = self.snapshotValid && !self.busy && dirty;
    // Unsaved changes: Discard replaces Back, so they aren't lost by accident.
    self.navigationItem.hidesBackButton = dirty;
    self.navigationItem.leftBarButtonItem = dirty
        ? [[UIBarButtonItem alloc] initWithTitle:@"Discard" style:UIBarButtonItemStylePlain
                                          target:self action:@selector(discardChanges)]
        : nil;
    self.navigationItem.leftBarButtonItem.enabled = !self.busy;
    [self updateInteractivePopGesture];
    [self.tableView reloadData];
    for (UIViewController *vc in self.navigationController.viewControllers)
        if ([vc isKindOfClass:DaemonGroupViewController.class]) [((UITableViewController *)vc).tableView reloadData];
}

#pragma mark Loading and saving

- (void)loadAllowingFullExploit:(BOOL)allowFullExploit
{
    if (self.busy) return;
    self.busy = YES;
    [self refreshUI];
    __weak typeof(self) weakSelf = self;
    settings_daemons_read_async(allowFullExploit, ^(NSDictionary *disabled, NSDictionary *running, NSString *message) {
        typeof(self) me = weakSelf;
        if (!me) return;
        me.busy = NO;
        if (disabled) {
            me.disabled = disabled;
            me.running = running;
            me.status = nil;
            me.snapshotValid = YES;
        } else {
            NSDictionary *failedDisabled = me.disabled;
            NSDictionary *failedRunning = me.running;
            NSString *failureStatus = me.status;
            daemons_invalidate_snapshot(&failedDisabled, &failedRunning, me.staged, &failureStatus, message);
            me.disabled = failedDisabled;
            me.running = failedRunning;
            me.status = failureStatus;
            me.snapshotValid = NO;
        }
        [me refreshUI];
        if (!disabled) [me handleFailure:message retry:^{ [weakSelf loadAllowingFullExploit:NO]; } from:me];
    });
}

- (void)setLabels:(NSArray<NSString *> *)labels disabled:(BOOL)disable from:(UIViewController *)presenter
{
    if (disable && !self.warningAccepted) { [self refreshUI]; [self showWarningIfNeeded]; return; }
    if (self.busy || !self.snapshotValid || !self.disabled) { [self refreshUI]; return; }
    for (NSString *label in labels) {
        if (disable && [self isLabelMissing:label] && ![self isLabelDisabled:label]) continue;   // nothing to disable
        // Legacy labels are enable-only; one staged disable would make the
        // whole Save fail (launchd_disabled_apply refuses the batch).
        if (!daemon_catalog_change_is_allowed(label, disable)) continue;
        if (disable == [self isLabelDisabled:label]) [self.staged removeObjectForKey:label];
        else self.staged[label] = @(disable);
    }
    [self refreshUI];
}

- (void)discardChanges
{
    [self.staged removeAllObjects];
    [self refreshUI];
}

// One confirmation for everything: what changes, and the warning of every
// group with one that gets disabled.
- (void)confirmSave
{
    if (!self.staged.count || self.busy) return;
    NSUInteger off = 0, on = 0;
    NSMutableArray<NSString *> *cautions = [NSMutableArray array];
    for (NSString *label in self.staged) self.staged[label].boolValue ? off++ : on++;
    for (CYDaemonGroup *g in daemon_catalog_groups()) {
        if (!g.caution) continue;
        for (NSString *label in g.labels) {
            if ([self.staged[label] boolValue]) { [cautions addObject:[NSString stringWithFormat:@"%@: %@", g.title, g.caution]]; break; }
        }
    }
    NSMutableArray *parts = [NSMutableArray array];
    if (off) [parts addObject:[NSString stringWithFormat:@"%lu 个守护进程%@将被禁用", (unsigned long)off, off == 1 ? @"" : @"s"]];
    if (on) [parts addObject:[NSString stringWithFormat:@"%lu 个将被启用", (unsigned long)on]];
    NSString *message = [[parts componentsJoinedByString:@", "] stringByAppendingString:@" 将在下次重启后生效。"];
    if (cautions.count) message = [message stringByAppendingFormat:@"\n\n⚠️ %@", [cautions componentsJoinedByString:@"\n\n⚠️ "]];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"保存更改？" message:message
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Save" style:off ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) { [self saveAllowingFullExploit:NO]; }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)saveAllowingFullExploit:(BOOL)allowFullExploit
{
    if (self.busy || !self.snapshotValid || !self.disabled || !self.staged.count) { [self refreshUI]; return; }
    NSDictionary<NSString *, NSNumber *> *changes = [self.staged copy];
    self.busy = YES;
    [self refreshUI];
    __weak typeof(self) weakSelf = self;
    settings_daemons_apply_async(changes, allowFullExploit, ^(BOOL ok, NSString *message) {
        typeof(self) me = weakSelf;
        if (!me) return;
        me.busy = NO;
        if (ok) {
            NSMutableDictionary *d = [me.disabled mutableCopy];
            for (NSString *label in changes) {
                if (changes[label].boolValue) d[label] = @YES;
                else [d removeObjectForKey:label];
            }
            me.disabled = d;
            daemons_note_change(changes.allKeys);
            // Only what was saved; a switch flipped meanwhile stays staged.
            for (NSString *label in changes)
                if ([me.staged[label] isEqual:changes[label]]) [me.staged removeObjectForKey:label];
        }
        [me refreshUI];
        if (!ok) [me handleFailure:message retry:^{ [weakSelf saveAllowingFullExploit:NO]; } from:me];
    });
}

// A failure that only a full exploit run can fix gets the shared Run Exploit
// popup (once per screen); `retry` runs after a successful run. Anything else
// is shown in an alert.
- (void)handleFailure:(NSString *)message retry:(void (^)(void))retry from:(UIViewController *)presenter
{
    if ([message isEqualToString:kSettingsFullExploitRequiredMessage]) {
        if (!self.disabled) self.status = kSettingsNoKernelAccessHint;
        [self refreshUI];
        // Already asked on this screen (e.g. a Save after kernel access was
        // lost): say why nothing happened instead of failing silently.
        if (settings_tool_exploit_was_offered(self)) {
            if (!presenter.view.window || presenter.presentedViewController) return;
            UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"守护进程管理"
                message:kSettingsNoKernelAccessHint preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [presenter presentViewController:ac animated:YES completion:nil];
            return;
        }
        settings_tool_needs_exploit(self, self.tableView, @"守护进程管理", retry);
        return;
    }
    if (!presenter.view.window || presenter.presentedViewController) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"守护进程管理" message:message ?: @"出了点问题。"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:ac animated:YES completion:nil];
}

#pragma mark Table

// Section 0: everyday groups. Section 1: the "Show Advanced" switch, then the
// advanced groups when it's on -- and always any advanced group that is
// (partly) disabled, so it can be switched back on.
- (BOOL)showAdvanced
{
    return [NSUserDefaults.standardUserDefaults boolForKey:kDaemonsShowAdvancedKey];
}

- (NSArray<CYDaemonGroup *> *)groupsInSection:(NSInteger)section
{
    NSMutableArray *out = [NSMutableArray array];
    for (CYDaemonGroup *g in daemon_catalog_groups()) {
        // The catalog covers several iOS versions: a group none of whose
        // daemons is a launchd job here can't do anything, so it isn't
        // shown -- unless one of its labels is disabled and could still be
        // switched back on.
        BOOL usable = NO;
        for (NSString *label in g.labels) usable |= ![self isLabelMissing:label] || [self isLabelDisabled:label];
        if (!usable) continue;
        if (section == 0 && !g.advanced) [out addObject:g];
        if (section == 1 && g.advanced) {
            BOOL anyOff = NO;
            for (NSString *label in g.labels) anyOff |= [self isLabelDisabled:label] || self.staged[label] != nil;
            if (self.showAdvanced || anyOff) [out addObject:g];
        }
    }
    // Never put removed labels back into a normal catalog group. They are
    // shown only when a persisted disabled entry exists, and only offer the
    // enable path that removes that entry.
    CYDaemonGroup *legacy = daemon_catalog_legacy_recovery_group(self.disabled);
    if (section == 1 && legacy) [out addObject:legacy];
    return out;
}

- (CYDaemonGroup *)groupAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger row = indexPath.row - (indexPath.section == 1 ? 1 : 0);
    NSArray *groups = [self groupsInSection:indexPath.section];
    return row >= 0 && row < (NSInteger)groups.count ? groups[(NSUInteger)row] : nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)[self groupsInSection:section].count + (section == 1 ? 1 : 0);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 1) return @"Advanced";
    if (self.status) return self.status;
    if (self.staged.count)
        return [NSString stringWithFormat:@"%lu 项未保存的更改%@ — 点按「保存」以应用", (unsigned long)self.staged.count,
                self.staged.count == 1 ? @"" : @"s"];
    return daemons_restart_pending() ? @"重启设备以应用你的更改" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0)
        return @"「已开启」表示该服务可以运行。点按「保存」会把改动写入 launchd 的 disabled.plist；"
               @"改动将在下次重启后生效。如果有你需要的东西停止工作，把它重新打开、"
               @"保存并重启。";
    return @"iOS 其他部分依赖的服务。禁用它们更容易引发问题。\n\n"
           @"⚠️ 禁用系统守护进程风险自负。如果 iOS 无法完成启动，只有恢复设备 "
           @"才能修复：它会抹除设备（除非你有备份），并安装最新的 iOS，而 Cyanide "
           @"很可能不支持该版本。请每次只改一项。";
}

- (UITableViewCell *)advancedSwitchCell
{
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"advanced"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"advanced"];
    UIListContentConfiguration *c = cell.defaultContentConfiguration;
    c.text = @"显示高级项";
    cell.contentConfiguration = c;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [UISwitch new];
    sw.on = self.showAdvanced;
    __weak typeof(self) weakSelf = self;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) {
        [weakSelf setShowAdvanced:((UISwitch *)a.sender).isOn];
    }] forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)setShowAdvanced:(BOOL)show
{
    if (!show) {
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:kDaemonsShowAdvancedKey];
        [self refreshUI];
        return;
    }
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"显示高级守护进程？"
                         message:@"这些服务被 iOS 的其他部分使用。禁用它们更容易破坏 "
                                 @"功能，最坏情况下会导致设备无法启动。届时恢复设备将会 "
                                 @"安装最新的 iOS，而 Cyanide 很可能不支持该版本。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        [self refreshUI];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Show" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:kDaemonsShowAdvancedKey];
        [self refreshUI];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 1 && indexPath.row == 0) return [self advancedSwitchCell];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"group"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"group"];
    CYDaemonGroup *g = [self groupAtIndexPath:indexPath];
    NSUInteger off = 0, unsaved = 0;
    for (NSString *label in g.labels) {
        off += [self willBeDisabled:label];
        unsaved += self.staged[label] != nil;
    }

    UIListContentConfiguration *c = [UIListContentConfiguration subtitleCellConfiguration];
    c.image = [UIImage systemImageNamed:g.symbol] ?: [UIImage systemImageNamed:@"gearshape"];
    c.imageProperties.tintColor = (g.caution || g.advanced) ? UIColor.systemOrangeColor : UIColor.systemBlueColor;
    c.text = g.title;
    NSUInteger running = 0;
    BOOL anyWarning = NO;
    for (NSString *label in g.labels) {
        if (self.running[label][@"pid"]) running++;
        BOOL warning = NO;
        [self statusForLabel:label warning:&warning];
        anyWarning |= warning;
    }
    NSMutableArray *facts = [NSMutableArray array];
    if (off > 0 && off < g.labels.count)
        [facts addObject:[NSString stringWithFormat:@"%lu / %lu 已禁用", (unsigned long)off, (unsigned long)g.labels.count]];
    BOOL hasLegacy = NO;
    for (NSString *label in g.labels) hasLegacy |= daemon_catalog_is_legacy_label(label);
    if (hasLegacy) {
        [facts addObject:@"旧版禁用记录；未检查作业是否存在"];
    } else {
        BOOL allMissing = self.running != nil;
        for (NSString *label in g.labels) allMissing &= [self isLabelMissing:label];
        if (allMissing)
            [facts addObject:@"此 iOS 版本中不存在该作业"];
        else if (self.running && ![self.running[g.labels.firstObject][@"unknown"] boolValue])
            [facts addObject:running ? [NSString stringWithFormat:@"%lu 个运行中", (unsigned long)running] : @"未运行"];
    }
    if (anyWarning) [facts addObject:@"已禁用但仍在运行"];
    if (unsaved) [facts insertObject:@"unsaved" atIndex:0];
    [facts addObject:g.summary];
    c.secondaryText = [facts componentsJoinedByString:@" · "];
    c.secondaryTextProperties.color = anyWarning ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
    c.secondaryTextProperties.numberOfLines = 0;
    cell.contentConfiguration = c;

    UISwitch *sw = [UISwitch new];
    sw.on = off == 0;   // partly disabled shows as off
    BOOL anyUsable = NO;
    for (NSString *label in g.labels) anyUsable |= ![self isLabelMissing:label] || [self isLabelDisabled:label];
    sw.enabled = self.snapshotValid && self.disabled && !self.busy && anyUsable;
    __weak typeof(self) weakSelf = self;
    NSArray *labels = g.labels;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) {
        typeof(self) me = weakSelf;
        [me setLabels:labels disabled:!((UISwitch *)a.sender).isOn from:me];
    }] forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CYDaemonGroup *g = [self groupAtIndexPath:indexPath];
    if (!g) return;
    DaemonGroupViewController *vc = [[DaemonGroupViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    vc.group = g;
    vc.owner = self;
    [self.navigationController pushViewController:vc animated:YES];
}

@end
