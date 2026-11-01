//
//  PackageDetailViewController.m
//  Cyanide
//

#import "PackageDetailViewController.h"
#import "CYIconBadge.h"
#import "PackageQueue.h"
#import "../LogTextView.h"
#import "../SettingsViewController.h"
#import "../tweaks/QuickLoader.h"
#import "../tweaks/RepoTweaks.h"
#import <math.h>


static NSString * const kCallRecordingDisclosureAcceptedDefault =
    @"installer.callRecordingSoundDisclosureAccepted";

static NSString *pkgdetail_string_or_empty(id value)
{
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static BOOL pkgdetail_js_identifier_valid(NSString *name)
{
    if (![name isKindOfClass:NSString.class] || name.length == 0) return NO;
    unichar first = [name characterAtIndex:0];
    if (![[NSCharacterSet letterCharacterSet] characterIsMember:first] && first != '_' && first != '$') return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$"];
    return [name rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static UIColor *pkgdetail_color_from_hex(NSString *hexString)
{
    if (![hexString isKindOfClass:NSString.class]) return UIColor.systemRedColor;
    NSString *clean = [hexString stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned rgb = 0;
    if (clean.length == 0 || ![[NSScanner scannerWithString:clean] scanHexInt:&rgb]) return UIColor.systemRedColor;
    return [UIColor colorWithRed:((rgb & 0xFF0000) >> 16) / 255.0
                           green:((rgb & 0x00FF00) >> 8) / 255.0
                            blue:(rgb & 0x0000FF) / 255.0
                           alpha:1.0];
}

static NSString *pkgdetail_hex_from_color(UIColor *color)
{
    if (![color isKindOfClass:UIColor.class]) return @"#FF0000";
    CGFloat r = 1.0, g = 0.0, b = 0.0, a = 1.0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return @"#FF0000";
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
            lround(r * 255.0), lround(g * 255.0), lround(b * 255.0)];
}

static NSMutableDictionary *pkgdetail_string_values_dictionary(id raw)
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (![raw isKindOfClass:NSDictionary.class]) return out;
    [(NSDictionary *)raw enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSString.class]) {
            out[key] = obj;
        }
    }];
    return out;
}

typedef NS_ENUM(NSInteger, PackageDetailSection) {
    PackageDetailSectionWarning = 0,
    PackageDetailSectionKnownIssues,
    PackageDetailSectionInfo,
    PackageDetailSectionAction,
    PackageDetailSectionSettings,
    PackageDetailSectionRepoOptions,
    PackageDetailSectionDescription,
    PackageDetailSectionCount,
};

@interface PackageDetailViewController ()
@property (nonatomic, strong) Package *package;
@property (nonatomic, copy)   NSArray<NSArray<NSString *> *> *infoRows;       // [[label, value], ...]
@property (nonatomic, copy)   NSArray<NSNumber *> *visibleSections;            // ordered PackageDetailSection values
@property (nonatomic, copy)   NSArray<NSDictionary<NSString *, NSString *> *> *settingsSummary;
@property (nonatomic, copy)   NSArray<NSDictionary *> *repoParams;
@property (nonatomic, strong) NSMutableDictionary *repoValues;
@end

@implementation PackageDetailViewController

+ (void)presentCallRecordingDisclosureIfNeededFromViewController:(UIViewController *)presenter
                                                  confirmHandler:(dispatch_block_t)confirmHandler
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ([d boolForKey:kCallRecordingDisclosureAcceptedDefault]) {
        if (confirmHandler) confirmHandler();
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"通话录音提示音说明"
                                            message:@"静音通话录音提示音，可能违反你所在地区或通话参与者所在地区的知情同意、告知或隐私法律。请仅在你获得许可并了解适用规则的场景下使用。\n\nCyanide 会修改 CallServices 的系统文件，并尽量保留备份。你可以通过此软件包恢复原始音频。"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"我已了解，静音"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *_) {
        [d setBool:YES forKey:kCallRecordingDisclosureAcceptedDefault];
        if (confirmHandler) confirmHandler();
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

// "Manual-control" packages are stateless from the Installer's POV: the user
// just queues an install or uninstall intent and confirms. The NanoRegistry
// override is the archetype. The detail view shows a menu instead of a
// toggle button so the user sees both options.
- (BOOL)isManualPackage
{
    return self.package.kind == PackageInstallKindNanoRegistry
        || self.package.kind == PackageInstallKindCallRecordingSound
        || self.package.kind == PackageInstallKindHideHomeBar;
}

- (BOOL)isDirectToolPackage
{
    return self.package.kind == PackageInstallKindDirectTool;
}

- (BOOL)isRepoTweakPackage
{
    return self.package.kind == PackageInstallKindRepoTweak;
}

- (BOOL)repoTweakHasUpdate
{
    if (![self isRepoTweakPackage]) return NO;
    if (self.package.isInstallDisabled) return NO;
    if (self.package.repoURL.length == 0 || self.package.repoTweakID.length == 0) return NO;
    NSString *installed = [NSUserDefaults.standardUserDefaults
        stringForKey:repotweaks_installed_version_key(self.package.repoURL, self.package.repoTweakID)];
    if (installed.length == 0 || self.package.version.length == 0) return NO;
    return repotweaks_compare_versions(self.package.version, installed) == NSOrderedDescending;
}

- (void)reloadRepoOptions
{
    if (![self isRepoTweakPackage]) {
        self.repoParams = @[];
        self.repoValues = [NSMutableDictionary dictionary];
        return;
    }

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *rawScript = [d stringForKey:repotweaks_script_defaults_key(self.package.repoURL, self.package.repoTweakID)] ?: @"";
    NSString *valuesKey = repotweaks_values_defaults_key(self.package.repoURL, self.package.repoTweakID);
    self.repoValues = pkgdetail_string_values_dictionary([d dictionaryForKey:valuesKey]);

    NSMutableArray *params = [NSMutableArray array];
    for (NSString *line in [rawScript componentsSeparatedByString:@"\n"]) {
        if (![line containsString:@"@param:"]) continue;
        NSArray *parts = [line componentsSeparatedByString:@"|"];
        if (parts.count < 4) continue;
        NSArray *typeParts = [parts[0] componentsSeparatedByString:@"@param:"];
        if (typeParts.count < 2) continue;

        NSString *type = [pkgdetail_string_or_empty(typeParts[1]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *varName = [pkgdetail_string_or_empty(parts[1]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *label = [pkgdetail_string_or_empty(parts[2]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *defValue = [pkgdetail_string_or_empty(parts[3]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!pkgdetail_js_identifier_valid(varName)) continue;

        NSMutableDictionary *param = [@{
            @"type": type,
            @"varName": varName,
            @"label": label.length ? label : varName,
            @"default": defValue,
        } mutableCopy];
        if (parts.count >= 5 && ([type isEqualToString:@"slider"] || [type isEqualToString:@"number"])) {
            NSString *range = [pkgdetail_string_or_empty(parts[4]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSArray *rangeParts = [range componentsSeparatedByString:@"-"];
            if (rangeParts.count == 2) {
                param[@"min"] = rangeParts[0];
                param[@"max"] = rangeParts[1];
            }
        }
        if (!self.repoValues[varName]) self.repoValues[varName] = defValue ?: @"";
        [params addObject:param];
    }
    self.repoParams = params;
    if (self.repoValues.count > 0) {
        [d setObject:self.repoValues forKey:valuesKey];
        [d synchronize];
    }
}

- (NSString *)manualActionTitleForIntent:(PackageQueueIntent)intent
{
    if (intent != PackageQueueIntentNone) {
        if (self.package.kind == PackageInstallKindNanoRegistry) {
            return (intent == PackageQueueIntentInstall) ? @"取消应用" : @"取消移除";
        }
        if (self.package.kind == PackageInstallKindCallRecordingSound) {
            return (intent == PackageQueueIntentInstall) ? @"取消静音" : @"取消还原";
        }
        if (self.package.kind == PackageInstallKindHideHomeBar) {
            return (intent == PackageQueueIntentInstall) ? @"取消隐藏" : @"取消还原";
        }
        return (intent == PackageQueueIntentInstall) ? @"取消停用" : @"取消启用";
    }
    if (self.package.kind == PackageInstallKindNanoRegistry) return @"Apply/Remove";
    if (self.package.kind == PackageInstallKindCallRecordingSound) return @"Silence/Restore";
    if (self.package.kind == PackageInstallKindHideHomeBar) return self.package.isInstalled ? @"Restore" : @"Hide";
    return @"Disable/Enable";
}

- (NSString *)manualStateText
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    if (self.package.kind == PackageInstallKindNanoRegistry) {
        if (intent == PackageQueueIntentInstall) return @"待应用";
        if (intent == PackageQueueIntentUninstall) return @"待移除";
        return @"手动控制";
    }
    if (self.package.kind == PackageInstallKindCallRecordingSound) {
        if (intent == PackageQueueIntentInstall) return @"待静音";
        if (intent == PackageQueueIntentUninstall) return @"待还原";
        return @"手动控制";
    }
    if (self.package.kind == PackageInstallKindHideHomeBar) {
        if (intent == PackageQueueIntentInstall) return @"待隐藏";
        if (intent == PackageQueueIntentUninstall) return @"待还原";
        return self.package.isInstalled ? @"Hidden" : @"Ready";
    }
    if (intent == PackageQueueIntentInstall) return @"待停用";
    if (intent == PackageQueueIntentUninstall) return @"待启用";
    return @"手动控制";
}

- (NSString *)toggleStateText
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    if ([self isRepoTweakPackage]) {
        BOOL hasUpdate = [self repoTweakHasUpdate];
        if (intent == PackageQueueIntentInstall) return hasUpdate ? @"待更新" : @"待安装";
        if (intent == PackageQueueIntentUninstall) return @"待移除";
        if (hasUpdate) return @"有可用更新";
        if (self.package.isInstalled) return @"Installed";
        return @"Available";
    }
    if (intent == PackageQueueIntentInstall) return @"待启用";
    if (intent == PackageQueueIntentUninstall) return @"待停用";
    if (self.package.isInstalled) return @"Installed";
    return @"Inactive";
}

- (UIColor *)toggleStateColor
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    if (intent == PackageQueueIntentInstall) return self.view.tintColor;
    if (intent == PackageQueueIntentUninstall) return UIColor.systemRedColor;
    if ([self repoTweakHasUpdate]) return UIColor.systemBlueColor;
    if (self.package.isInstalled) return UIColor.systemGreenColor;
    return UIColor.secondaryLabelColor;
}

- (NSString *)packageStateText
{
    if ([self isDirectToolPackage]) return @"手动控制";
    return [self isManualPackage] ? [self manualStateText] : [self toggleStateText];
}

- (UIColor *)packageStateColor
{
    if ([self isDirectToolPackage]) return UIColor.secondaryLabelColor;
    return [self isManualPackage] ? [self manualStateColor] : [self toggleStateColor];
}

- (UIColor *)manualStateColor
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    if (intent != PackageQueueIntentNone) return self.view.tintColor;
    if (self.package.kind == PackageInstallKindHideHomeBar && self.package.isInstalled) {
        return UIColor.systemGreenColor;
    }
    return UIColor.secondaryLabelColor;
}

- (BOOL)presentQueueConflictIfNeededForIntent:(PackageQueueIntent)intent
{
    NSString *reason = nil;
    if ([[PackageQueue sharedQueue] canQueueIntent:intent
                                       forPackage:self.package
                                           reason:&reason]) {
        return NO;
    }

    BOOL hideHomeBarReason = [reason containsString:@"隐藏主屏横条"];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:(hideHomeBarReason ? @"单独运行「隐藏主屏横条」" : @"无法加入安装队列")
                                            message:reason ?: @"此软件包暂时无法加入队列。"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return YES;
}

- (NSArray<NSArray<NSString *> *> *)currentInfoRows
{
    NSMutableArray<NSArray<NSString *> *> *rows = [self.infoRows mutableCopy];
    [rows addObject:@[@"State", [self packageStateText]]];
    return rows;
}

- (void)queueManualIntent:(PackageQueueIntent)intent
{
    if ([self presentQueueConflictIfNeededForIntent:intent]) return;

    if (self.package.kind == PackageInstallKindNanoRegistry) {
        log_user("[INSTALLER] Pending watch-pairing %s\n",
                 intent == PackageQueueIntentInstall ? "apply" : "remove");
    } else if (self.package.kind == PackageInstallKindCallRecordingSound) {
        log_user("[INSTALLER] Pending call-recording sound %s\n",
                 intent == PackageQueueIntentInstall ? "silence" : "restore");
    } else if (self.package.kind == PackageInstallKindHideHomeBar) {
        log_user("[INSTALLER] Pending home bar %s\n",
                 intent == PackageQueueIntentInstall ? "hide" : "restore");
    } else {
        log_user("[INSTALLER] Pending OTA %s\n",
                 intent == PackageQueueIntentInstall ? "disable" : "enable");
    }
    [[PackageQueue sharedQueue] queueIntent:intent forPackage:self.package];
}

- (UIMenu *)manualActionMenu
{
    if (self.package.kind == PackageInstallKindNanoRegistry) {
        UIAction *apply = [UIAction actionWithTitle:@"应用配对覆盖"
                                              image:[UIImage systemImageNamed:@"applewatch.radiowaves.left.and.right"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *_) {
            [self queueManualIntent:PackageQueueIntentInstall];
        }];

        UIAction *remove = [UIAction actionWithTitle:@"移除配对覆盖"
                                               image:[UIImage systemImageNamed:@"xmark.circle"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *_) {
            [self queueManualIntent:PackageQueueIntentUninstall];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;

        return [UIMenu menuWithTitle:@"Watch Pairing Override" children:@[apply, remove]];
    }

    if (self.package.kind == PackageInstallKindCallRecordingSound) {
        UIAction *silence = [UIAction actionWithTitle:@"静音提示音"
                                                image:[UIImage systemImageNamed:@"speaker.slash.fill"]
                                           identifier:nil
                                              handler:^(__kindof UIAction *_) {
            [PackageDetailViewController
                presentCallRecordingDisclosureIfNeededFromViewController:self
                                                          confirmHandler:^{
                [self queueManualIntent:PackageQueueIntentInstall];
            }];
        }];
        silence.attributes = UIMenuElementAttributesDestructive;

        UIAction *restore = [UIAction actionWithTitle:@"恢复原始音频"
                                                image:[UIImage systemImageNamed:@"speaker.wave.2.fill"]
                                           identifier:nil
                                              handler:^(__kindof UIAction *_) {
            [self queueManualIntent:PackageQueueIntentUninstall];
        }];

        return [UIMenu menuWithTitle:@"Call Recording Sound" children:@[silence, restore]];
    }

    if (self.package.kind == PackageInstallKindHideHomeBar) {
        UIAction *hide = [UIAction actionWithTitle:@"隐藏主屏横条"
                                             image:[UIImage systemImageNamed:@"line.3.horizontal"]
                                        identifier:nil
                                           handler:^(__kindof UIAction *_) {
            [self queueManualIntent:PackageQueueIntentInstall];
        }];
        hide.attributes = UIMenuElementAttributesDestructive;

        UIAction *restore = [UIAction actionWithTitle:@"恢复主屏横条"
                                                image:[UIImage systemImageNamed:@"arrow.clockwise"]
                                           identifier:nil
                                              handler:^(__kindof UIAction *_) {
            [self queueManualIntent:PackageQueueIntentUninstall];
        }];

        return [UIMenu menuWithTitle:@"主屏横条" children:@[hide, restore]];
    }

    UIAction *disable = [UIAction actionWithTitle:@"停用 OTA 更新"
                                            image:[UIImage systemImageNamed:@"icloud.slash"]
                                       identifier:nil
                                          handler:^(__kindof UIAction *_) {
        [self queueManualIntent:PackageQueueIntentInstall];
    }];
    disable.attributes = UIMenuElementAttributesDestructive;

    UIAction *enable = [UIAction actionWithTitle:@"启用 OTA 更新"
                                           image:[UIImage systemImageNamed:@"icloud"]
                                      identifier:nil
                                         handler:^(__kindof UIAction *_) {
        [self queueManualIntent:PackageQueueIntentUninstall];
    }];

    return [UIMenu menuWithTitle:@"OTA 更新" children:@[disable, enable]];
}

- (instancetype)initWithPackage:(Package *)package
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _package = package;
        [self reloadRepoOptions];
        _infoRows = @[
            @[@"Author",   package.author],
            @[@"Version",  package.version],
        ];
        NSMutableArray<NSNumber *> *sections = [NSMutableArray array];
        if (package.unstableWarning.length > 0) {
            [sections addObject:@(PackageDetailSectionWarning)];
        }
        if (package.knownIssues.count > 0) {
            [sections addObject:@(PackageDetailSectionKnownIssues)];
        }
        if (package.settingsSection != NSIntegerMax && !package.isInstallDisabled) {
            [sections addObject:@(PackageDetailSectionAction)];
        }
        _settingsSummary = [SettingsViewController settingsSummaryForSection:package.settingsSection];
        if (_settingsSummary.count > 0) {
            [sections addObject:@(PackageDetailSectionSettings)];
        }
        if (_repoParams.count > 0) {
            [sections addObject:@(PackageDetailSectionRepoOptions)];
        }
        [sections addObject:@(PackageDetailSectionInfo)];
        [sections addObject:@(PackageDetailSectionDescription)];
        _visibleSections = sections;
    }
    return self;
}

- (PackageDetailSection)sectionAtIndex:(NSInteger)index
{
    return (PackageDetailSection)[self.visibleSections[index] integerValue];
}

- (BOOL)hasSettingsBundle
{
    return self.package.settingsSection != NSIntegerMax;
}

- (BOOL)requiresThemeSelection
{
    return [self.package.identifier isEqualToString:@"com.darksword.themer"] ||
           [self.package.identifier isEqualToString:@"com.darksword.snowboardlite"];
}

- (BOOL)isLiveWPPackage
{
    return [self.package.identifier isEqualToString:@"com.darksword.livewp"];
}

- (BOOL)needsThemeBeforeInstall
{
    if (![self requiresThemeSelection] || self.package.isInstalled) return NO;
    if ([self.package.identifier isEqualToString:@"com.darksword.snowboardlite"]) {
        return !settings_snowboardlite_has_selected_theme();
    }
    return !settings_themer_has_selected_theme();
}

- (BOOL)needsLiveWPVideoBeforeInstall
{
    return [self isLiveWPPackage] &&
           !self.package.isInstalled &&
           ![SettingsViewController liveWPHasSelectedVideo];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.package.name;
    // The tweak name is shown prominently (centered) in the table header below,
    // so suppress the large nav title here — otherwise it duplicates the name
    // and hangs to the far left of the inset-grouped cards. This gives the
    // standard "detail page" look (small centered nav title, big content title).
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.tableHeaderView = [self buildHeaderView];
    [self updateActionButton];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:PackageQueueDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:kSettingsActionsDidCompleteNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadRepoOptions];
    self.settingsSummary = [SettingsViewController settingsSummaryForSection:self.package.settingsSection];
    self.tableView.tableHeaderView = [self buildHeaderView];
    [self.tableView reloadData];
    [self updateActionButton];
}

- (void)queueDidChange:(NSNotification *)note
{
    if (!self.isViewLoaded) return;
    self.tableView.tableHeaderView = [self buildHeaderView];
    [self.tableView reloadData];
    [self updateActionButton];
}

#pragma mark - Header

- (UIView *)buildHeaderView
{
    CGFloat width = self.view.bounds.size.width;
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = UIColor.clearColor;

    // Icon
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.image = CYIconBadgeImage(self.package.symbolName, CYSpectrumColor(self.package.name.hash), 60.0);
    [header addSubview:iconView];

    // Name
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.text = self.package.name;
    nameLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    nameLabel.textColor = UIColor.labelColor;
    nameLabel.textAlignment = NSTextAlignmentCenter;
    [header addSubview:nameLabel];

    // Subtitle: Category · Version
    UILabel *subLabel = [[UILabel alloc] init];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subLabel.text = [NSString stringWithFormat:@"%@  ·  版本 %@", self.package.category, self.package.version];
    subLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    subLabel.textColor = [UIColor.labelColor colorWithAlphaComponent:0.45];
    subLabel.textAlignment = NSTextAlignmentCenter;
    [header addSubview:subLabel];

    // Status badge (optional)
    UIView *badge = nil;
    if (self.package.isInstallDisabled && !self.package.isInstalled) {
        badge = [self badgeWithText:@"已禁用"
                         background:[UIColor.systemRedColor colorWithAlphaComponent:0.16]
                          textColor:UIColor.systemRedColor];
    } else if ([self isDirectToolPackage]) {
        badge = [self badgeWithText:@"MANUAL"
                         background:[UIColor.secondaryLabelColor colorWithAlphaComponent:0.16]
                          textColor:UIColor.secondaryLabelColor];
    } else if ([self isManualPackage]) {
        UIColor *color = [self manualStateColor];
        badge = [self badgeWithText:[self manualStateText].uppercaseString
                         background:[color colorWithAlphaComponent:0.16]
                          textColor:color];
    } else if (intent != PackageQueueIntentNone || self.package.isInstalled) {
        UIColor *color = [self packageStateColor];
        badge = [self badgeWithText:[self packageStateText].uppercaseString
                         background:[color colorWithAlphaComponent:0.16]
                          textColor:color];
    } else if (self.package.creatorOnly) {
        badge = [self badgeWithText:@"开发中"
                         background:[UIColor.systemPurpleColor colorWithAlphaComponent:0.16]
                          textColor:UIColor.systemPurpleColor];
    } else if ([self.package.category caseInsensitiveCompare:@"Beta"] == NSOrderedSame) {
        badge = [self badgeWithText:@"BETA"
                         background:[UIColor.systemPurpleColor colorWithAlphaComponent:0.16]
                          textColor:UIColor.systemPurpleColor];
    } else if (self.package.experimental) {
        badge = [self badgeWithText:@"EXPERIMENTAL"
                         background:[UIColor.systemRedColor colorWithAlphaComponent:0.16]
                          textColor:UIColor.systemRedColor];
    } else if (self.package.isInstallDisabled) {
        badge = [self badgeWithText:@"已禁用"
                         background:[UIColor.systemRedColor colorWithAlphaComponent:0.16]
                          textColor:UIColor.systemRedColor];
    }
    if (badge) {
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:badge];
    }

    NSMutableArray<NSLayoutConstraint *> *cs = [NSMutableArray array];
    [cs addObjectsFromArray:@[
        [iconView.topAnchor      constraintEqualToAnchor:header.topAnchor constant:16.0],
        [iconView.centerXAnchor  constraintEqualToAnchor:header.centerXAnchor],
        [iconView.widthAnchor    constraintEqualToConstant:60.0],
        [iconView.heightAnchor   constraintEqualToConstant:54.0],

        [nameLabel.topAnchor      constraintEqualToAnchor:iconView.bottomAnchor constant:12.0],
        [nameLabel.leadingAnchor  constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [nameLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],

        [subLabel.topAnchor       constraintEqualToAnchor:nameLabel.bottomAnchor constant:3.0],
        [subLabel.leadingAnchor   constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [subLabel.trailingAnchor  constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
    ]];

    // Anchor the *last* element to the bottom so the header self-sizes. Bumped
    // the sub→badge gap from 6→12 and the badge→bottom gap to 14 so the pill
    // gets clear breathing room above and below (it was clipping the
    // description box below before).
    if (badge) {
        [cs addObjectsFromArray:@[
            [badge.topAnchor       constraintEqualToAnchor:subLabel.bottomAnchor constant:12.0],
            [badge.centerXAnchor   constraintEqualToAnchor:header.centerXAnchor],
            [badge.bottomAnchor    constraintEqualToAnchor:header.bottomAnchor constant:-14.0],
        ]];
    } else {
        [cs addObject:[subLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12.0]];
    }
    [NSLayoutConstraint activateConstraints:cs];

    // tableHeaderView needs an explicit frame — auto layout inside it doesn't
    // size the slot. Ask the view for its natural height at the table's width.
    CGSize fit = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                       withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    header.frame = CGRectMake(0, 0, width, fit.height);
    return header;
}

- (UIView *)badgeWithText:(NSString *)text background:(UIColor *)bg textColor:(UIColor *)fg
{
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = bg;
    container.layer.cornerRadius = 12.0;
    container.layer.cornerCurve = kCACornerCurveContinuous;
    container.layer.masksToBounds = YES;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
    label.textColor = fg;
    label.textAlignment = NSTextAlignmentCenter;
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor      constraintEqualToAnchor:container.topAnchor constant:4.0],
        [label.bottomAnchor   constraintEqualToAnchor:container.bottomAnchor constant:-4.0],
        [label.leadingAnchor  constraintEqualToAnchor:container.leadingAnchor constant:10.0],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-10.0],
    ]];
    return container;
}

#pragma mark - Action button

- (void)updateActionButton
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    BOOL installed = self.package.isInstalled;
    BOOL manual = [self isManualPackage];
    BOOL directTool = [self isDirectToolPackage];

    NSString *title;
    UIBarButtonItemStyle style = UIBarButtonItemStylePlain;
    UIColor *tint = nil;
    if (self.package.isInstallDisabled && !installed && intent == PackageQueueIntentNone) {
        title = @"Disabled";
        tint = UIColor.secondaryLabelColor;
    } else if (directTool) {
        title = @"打开控制";
        tint = self.view.tintColor;
        style = UIBarButtonItemStyleDone;
    } else if (manual) {
        title = [self manualActionTitleForIntent:intent];
        tint = (intent != PackageQueueIntentNone)
            ? UIColor.secondaryLabelColor
            : self.view.tintColor;
        if (intent == PackageQueueIntentNone) style = UIBarButtonItemStyleDone;
    } else if (intent != PackageQueueIntentNone) {
        title = @"Cancel";
        tint = UIColor.secondaryLabelColor;
    } else if (installed && [self isLiveWPPackage] && [self hasSettingsBundle]) {
        title = @"更换视频";
        tint = self.view.tintColor;
        style = UIBarButtonItemStyleDone;
    } else if ([self repoTweakHasUpdate]) {
        title = @"Update";
        tint = self.view.tintColor;
        style = UIBarButtonItemStyleDone;
    } else if (installed && [self isRepoTweakPackage]) {
        title = @"Remove";
        tint = UIColor.systemRedColor;
    } else if (installed) {
        title = @"Deactivate";
        tint = UIColor.systemRedColor;
    } else if (self.package.creatorOnly) {
        title = @"开发中";
        tint = UIColor.secondaryLabelColor;
    } else if (self.package.isInstallDisabled) {
        title = @"Disabled";
        tint = UIColor.secondaryLabelColor;
    } else if ([self needsThemeBeforeInstall]) {
        title = @"选择主题";
        style = UIBarButtonItemStyleDone;
    } else if ([self needsLiveWPVideoBeforeInstall]) {
        title = @"选择视频";
        style = UIBarButtonItemStyleDone;
    } else if ([self isRepoTweakPackage]) {
        title = @"Install";
        style = UIBarButtonItemStyleDone;
    } else {
        title = @"Activate";
        style = UIBarButtonItemStyleDone;
    }

    BOOL useMenu = manual && intent == PackageQueueIntentNone;
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:title
                                                             style:style
                                                            target:useMenu ? nil : self
                                                            action:useMenu ? nil : @selector(didTapAction)];
    if (useMenu) {
        item.menu = [self manualActionMenu];
    }
    if (tint) item.tintColor = tint;
    item.enabled = !self.package.isInstallDisabled || installed || intent != PackageQueueIntentNone;
    self.navigationItem.rightBarButtonItem = item;
}

- (void)didTapAction
{
    PackageQueueIntent intent = [[PackageQueue sharedQueue] intentForPackage:self.package];
    if (intent != PackageQueueIntentNone) {
        log_user("[INSTALLER] Removed %s from queue\n", self.package.name.UTF8String);
        [[PackageQueue sharedQueue] removePackage:self.package];
        return;
    }
    if (self.package.creatorOnly) {
        return;
    }
    if (self.package.isInstallDisabled && !self.package.isInstalled) {
        log_user("[INSTALLER] %s is disabled for now: %s\n",
                 self.package.name.UTF8String,
                 self.package.installDisabledReason.UTF8String);
        return;
    }
    if ([self needsThemeBeforeInstall]) {
        [self promptSelectThemeBeforeInstall];
        return;
    }
    if ([self needsLiveWPVideoBeforeInstall]) {
        [self navigateToSettingsSection];
        return;
    }
    if ([self isDirectToolPackage]) {
        [self navigateToSettingsSection];
        return;
    }
    if (self.package.isInstalled && [self isLiveWPPackage] && [self hasSettingsBundle]) {
        [self navigateToSettingsSection];
        return;
    }
    if (NO && !self.package.isInstalled && [self hasSettingsBundle]) {
        [self promptConfigureBeforeInstall];
        return;
    }
    // Manual packages dispatch via menu — didTapAction should never run for
    // them when intent == None (the bar item carries a UIMenu instead of a
    // selector target).
    if ([self isManualPackage]) {
        return;
    } else if ([self repoTweakHasUpdate]) {
        if ([self presentQueueConflictIfNeededForIntent:PackageQueueIntentInstall]) return;
        log_user("[INSTALLER] Pending update: %s\n", self.package.name.UTF8String);
        [[PackageQueue sharedQueue] queueIntent:PackageQueueIntentInstall forPackage:self.package];
        return;
    } else if (self.package.isInstalled) {
        if ([self presentQueueConflictIfNeededForIntent:PackageQueueIntentUninstall]) return;
        log_user("[INSTALLER] Pending %s: %s\n",
                 [self isRepoTweakPackage] ? "removal" : "deactivation",
                 self.package.name.UTF8String);
    } else {
        if ([self presentQueueConflictIfNeededForIntent:PackageQueueIntentInstall]) return;
        log_user("[INSTALLER] Pending %s: %s\n",
                 [self isRepoTweakPackage] ? "install" : "activation",
                 self.package.name.UTF8String);
    }
    [[PackageQueue sharedQueue] toggleForPackage:self.package];
}

- (void)promptSelectThemeBeforeInstall
{
    BOOL snowBoardLite = [self.package.identifier isEqualToString:@"com.darksword.snowboardlite"];
    NSString *message = snowBoardLite
        ? @"SnowBoard Lite 需要先选择主题才能激活。请先选择「iOS 6 主题」，或导入一个 SnowBoard/IconBundles 主题。"
        : @"图标主题需要先选择主题才能激活。请先选择「iOS 6 主题」，或导入一个自定义主题。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择主题"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"打开主题设置"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *_) {
        [self navigateToSettingsSection];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptConfigureBeforeInstall
{
    NSString *msg = [NSString stringWithFormat:
        @"%@ 有可配置的选项。建议先设置好，这样首次激活时就会按你的偏好生效。",
        self.package.name];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"激活前先自定义？"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"先配置"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *_) {
        [self navigateToSettingsSection];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"仍然激活"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *_) {
        if ([self presentQueueConflictIfNeededForIntent:PackageQueueIntentInstall]) return;
        log_user("[INSTALLER] Pending activation: %s\n", self.package.name.UTF8String);
        [[PackageQueue sharedQueue] toggleForPackage:self.package];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UITableViewCell *)repoOptionCellForParam:(NSDictionary *)param
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                   reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = pkgdetail_string_or_empty(param[@"label"]);

    NSString *varName = pkgdetail_string_or_empty(param[@"varName"]);
    NSString *type = pkgdetail_string_or_empty(param[@"type"]);
    NSString *currentValue = pkgdetail_string_or_empty(self.repoValues[varName]);
    NSString *valuesKey = repotweaks_values_defaults_key(self.package.repoURL, self.package.repoTweakID);
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;

    void (^saveValues)(void) = ^{
        [d setObject:self.repoValues forKey:valuesKey];
        if (self.package.isInstalled) {
            if (self.package.repoNativeEnabledKey.length > 0) {
                [self.package syncRepoTweakOptionsToNativeSettings];
                settings_mark_tweak_needs_apply(self.package.repoNativeEnabledKey);
            } else if (quickloader_is_repo_tweak_installed(self.package.repoURL, self.package.repoTweakID)) {
                quickloader_refresh_active_repo_tweak();
                settings_mark_tweak_needs_apply(kSettingsQuickLoaderEnabled);
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                                object:nil];
        }
        [d synchronize];
    };

    if ([type isEqualToString:@"switch"]) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [currentValue isEqualToString:@"true"] || [currentValue boolValue];
        [sw addAction:[UIAction actionWithHandler:^(__kindof UIAction *_) {
            self.repoValues[varName] = sw.isOn ? @"true" : @"false";
            saveValues();
        }] forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }

    if ([type isEqualToString:@"text"]) {
        UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 170, 30)];
        tf.textAlignment = NSTextAlignmentRight;
        tf.textColor = UIColor.secondaryLabelColor;
        tf.text = currentValue;
        [tf addAction:[UIAction actionWithHandler:^(__kindof UIAction *_) {
            self.repoValues[varName] = tf.text ?: @"";
            saveValues();
        }] forControlEvents:UIControlEventEditingChanged];
        cell.accessoryView = tf;
        return cell;
    }

    if ([type isEqualToString:@"color"]) {
        UIColorWell *well = [[UIColorWell alloc] init];
        well.translatesAutoresizingMaskIntoConstraints = NO;
        well.title = pkgdetail_string_or_empty(param[@"label"]);
        well.selectedColor = pkgdetail_color_from_hex(currentValue.length ? currentValue : @"#FF0000");
        [well addAction:[UIAction actionWithHandler:^(__kindof UIAction *_) {
            self.repoValues[varName] = pkgdetail_hex_from_color(well.selectedColor);
            saveValues();
        }] forControlEvents:UIControlEventValueChanged];
        [cell.contentView addSubview:well];
        [NSLayoutConstraint activateConstraints:@[
            [well.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [well.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [well.widthAnchor constraintEqualToConstant:32.0],
            [well.heightAnchor constraintEqualToConstant:32.0],
        ]];
        return cell;
    }

    if ([type isEqualToString:@"slider"] || [type isEqualToString:@"number"]) {
        UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(0, 0, 220, 30)];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.spacing = 10.0;
        stack.alignment = UIStackViewAlignmentCenter;

        UISlider *slider = [[UISlider alloc] init];
        slider.minimumValue = param[@"min"] ? [param[@"min"] floatValue] : 0.0f;
        slider.maximumValue = param[@"max"] ? [param[@"max"] floatValue] : 1.0f;
        float defVal = param[@"default"] ? [param[@"default"] floatValue] : slider.minimumValue;
        slider.value = currentValue.length ? [currentValue floatValue] : defVal;

        UILabel *valueLabel = [[UILabel alloc] init];
        valueLabel.textColor = UIColor.secondaryLabelColor;
        valueLabel.font = [UIFont systemFontOfSize:14.0];
        [valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisHorizontal];

        void (^updateLabel)(float) = ^(float value) {
            valueLabel.text = fabs(value - defVal) < 0.01
                ? [NSString stringWithFormat:@"%.2f（默认）", value]
                : [NSString stringWithFormat:@"%.2f", value];
        };
        updateLabel(slider.value);

        [stack addArrangedSubview:slider];
        [stack addArrangedSubview:valueLabel];

        [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction *_) {
            updateLabel(slider.value);
        }] forControlEvents:UIControlEventValueChanged];
        [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction *_) {
            self.repoValues[varName] = [NSString stringWithFormat:@"%.2f", slider.value];
            saveValues();
        }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        cell.accessoryView = stack;
        return cell;
    }

    cell.detailTextLabel.text = currentValue;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    return cell;
}

#pragma mark - Data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.visibleSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch ([self sectionAtIndex:section]) {
        case PackageDetailSectionWarning:      return 1;
        case PackageDetailSectionKnownIssues:  return 1;
        case PackageDetailSectionInfo:         return (NSInteger)[self currentInfoRows].count;
        case PackageDetailSectionAction:       return 1;
        case PackageDetailSectionSettings:     return (NSInteger)self.settingsSummary.count;
        case PackageDetailSectionRepoOptions:  return (NSInteger)self.repoParams.count;
        case PackageDetailSectionDescription:  return [self isRepoTweakPackage] ? 2 : 1;
        case PackageDetailSectionCount:        return 0;
    }
    return 0;
}

- (NSString *)detailSectionTitle:(NSInteger)section
{
    switch ([self sectionAtIndex:section]) {
        case PackageDetailSectionKnownIssues:  return @"已知问题";
        case PackageDetailSectionAction:       return @"Configure";
        case PackageDetailSectionSettings:     return @"当前设置";
        case PackageDetailSectionRepoOptions:  return @"Options";
        default: return nil;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSString *title = [self detailSectionTitle:section];
    return title ? CYSectionHeaderView(title) : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return [self detailSectionTitle:section] ? 46.0 : 0.0;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if ([self sectionAtIndex:section] == PackageDetailSectionAction) {
        return @"设置可在激活前后随时修改。";
    }
    if ([self sectionAtIndex:section] == PackageDetailSectionRepoOptions) {
        return self.package.repoTweakUsesQuickLoader
            ? @"安装前会先保存在这里；排队的软件包运行时，QuickLoader 会应用这些值。"
            : @"安装前会先保存在这里；Cyanide 会通过原生软件包后端应用这些值。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch ([self sectionAtIndex:indexPath.section]) {
        case PackageDetailSectionWarning: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"WarningCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                              reuseIdentifier:@"WarningCell"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            // Wipe any previous subviews from cell reuse before rebuilding.
            for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];
            cell.textLabel.text   = nil;
            cell.imageView.image  = nil;
            cell.backgroundColor  = [UIColor.systemRedColor colorWithAlphaComponent:0.14];

            UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
            icon.translatesAutoresizingMaskIntoConstraints = NO;
            icon.tintColor = UIColor.systemRedColor;
            icon.preferredSymbolConfiguration =
                [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold];
            [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [cell.contentView addSubview:icon];

            UILabel *label = [[UILabel alloc] init];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            label.text = self.package.unstableWarning;
            label.textColor = UIColor.systemRedColor;
            label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
            label.numberOfLines = 0;
            [cell.contentView addSubview:label];

            UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
            [NSLayoutConstraint activateConstraints:@[
                [icon.leadingAnchor    constraintEqualToAnchor:m.leadingAnchor],
                [icon.topAnchor        constraintEqualToAnchor:m.topAnchor constant:2.0],
                [icon.widthAnchor      constraintEqualToConstant:22.0],

                [label.leadingAnchor   constraintEqualToAnchor:icon.trailingAnchor constant:10.0],
                [label.trailingAnchor  constraintEqualToAnchor:m.trailingAnchor],
                [label.topAnchor       constraintEqualToAnchor:m.topAnchor],
                [label.bottomAnchor    constraintEqualToAnchor:m.bottomAnchor],
            ]];
            return cell;
        }
        case PackageDetailSectionKnownIssues: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"KnownIssuesCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                              reuseIdentifier:@"KnownIssuesCell"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];
            cell.textLabel.text   = nil;
            cell.imageView.image  = nil;
            cell.backgroundColor  = UIColor.clearColor;

            NSArray<NSString *> *issues = self.package.knownIssues;
            UIColor *accent = UIColor.systemOrangeColor;

            UIView *card = [[UIView alloc] init];
            card.translatesAutoresizingMaskIntoConstraints = NO;
            card.backgroundColor = [accent colorWithAlphaComponent:0.06];
            card.layer.borderColor = [accent colorWithAlphaComponent:0.35].CGColor;
            card.layer.borderWidth = 1.0;
            card.layer.cornerRadius = 10.0;
            card.layer.cornerCurve = kCACornerCurveContinuous;
            card.layer.masksToBounds = YES;

            NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
            ps.headIndent = 12.0;
            ps.firstLineHeadIndent = 0.0;
            ps.paragraphSpacing = 6.0;
            ps.lineSpacing = 1.0;

            NSDictionary *bulletAttrs = @{
                NSFontAttributeName: [UIFont systemFontOfSize:14.0],
                NSForegroundColorAttributeName: accent,
                NSParagraphStyleAttributeName: ps,
            };
            NSDictionary *textAttrs = @{
                NSFontAttributeName: [UIFont systemFontOfSize:14.0],
                NSForegroundColorAttributeName: UIColor.labelColor,
                NSParagraphStyleAttributeName: ps,
            };

            NSMutableAttributedString *body = [[NSMutableAttributedString alloc] init];
            for (NSUInteger i = 0; i < issues.count; i++) {
                if (i > 0) [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
                [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"•  " attributes:bulletAttrs]];
                [body appendAttributedString:[[NSAttributedString alloc] initWithString:issues[i] attributes:textAttrs]];
            }

            UILabel *bodyLabel = [[UILabel alloc] init];
            bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
            bodyLabel.attributedText = body;
            bodyLabel.numberOfLines = 0;

            [card addSubview:bodyLabel];
            [cell.contentView addSubview:card];

            UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
            [NSLayoutConstraint activateConstraints:@[
                [card.leadingAnchor    constraintEqualToAnchor:m.leadingAnchor],
                [card.trailingAnchor   constraintEqualToAnchor:m.trailingAnchor],
                [card.topAnchor        constraintEqualToAnchor:m.topAnchor],
                [card.bottomAnchor     constraintEqualToAnchor:m.bottomAnchor],

                [bodyLabel.leadingAnchor   constraintEqualToAnchor:card.leadingAnchor constant:14],
                [bodyLabel.trailingAnchor  constraintEqualToAnchor:card.trailingAnchor constant:-14],
                [bodyLabel.topAnchor       constraintEqualToAnchor:card.topAnchor constant:12],
                [bodyLabel.bottomAnchor    constraintEqualToAnchor:card.bottomAnchor constant:-12],
            ]];
            return cell;
        }
        case PackageDetailSectionInfo: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"InfoCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                              reuseIdentifier:@"InfoCell"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            NSArray<NSArray<NSString *> *> *rows = [self currentInfoRows];
            NSArray<NSString *> *row = indexPath.row < (NSInteger)rows.count ? rows[indexPath.row] : @[];
            NSString *label = row.count > 0 ? row[0] : @"";
            NSString *value = row.count > 1 ? row[1] : @"";
            cell.textLabel.text = label;
            cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
            cell.detailTextLabel.text = value;
            cell.detailTextLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
            cell.detailTextLabel.textColor = [label isEqualToString:@"State"]
                ? [self packageStateColor]
                : [UIColor.labelColor colorWithAlphaComponent:0.55];
            cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            return cell;
        }
        case PackageDetailSectionDescription: {
            if ([self isRepoTweakPackage] && indexPath.row == 1) {
                UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                UILabel *note = [[UILabel alloc] init];
                note.translatesAutoresizingMaskIntoConstraints = NO;
                note.numberOfLines = 0;
                note.text = @"请只安装来自你信任来源的脚本。";
                note.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
                note.textColor = [UIColor.labelColor colorWithAlphaComponent:0.35];
                [cell.contentView addSubview:note];
                UILayoutGuide *nm = cell.contentView.layoutMarginsGuide;
                [NSLayoutConstraint activateConstraints:@[
                    [note.topAnchor      constraintEqualToAnchor:nm.topAnchor],
                    [note.bottomAnchor   constraintEqualToAnchor:nm.bottomAnchor],
                    [note.leadingAnchor  constraintEqualToAnchor:nm.leadingAnchor],
                    [note.trailingAnchor constraintEqualToAnchor:nm.trailingAnchor],
                ]];
                return cell;
            }

            static NSString *kDescID = @"DescCell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDescID];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                              reuseIdentifier:kDescID];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];
            cell.textLabel.text = nil;

            UILabel *descLabel = [[UILabel alloc] init];
            descLabel.translatesAutoresizingMaskIntoConstraints = NO;
            descLabel.numberOfLines = 0;
            descLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
            descLabel.textColor = [UIColor.labelColor colorWithAlphaComponent:0.75];

            NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
            ps.lineSpacing = 4.0;
            ps.paragraphSpacing = 12.0;
            descLabel.attributedText = [[NSAttributedString alloc]
                initWithString:self.package.longDescription ?: @""
                    attributes:@{
                        NSFontAttributeName: descLabel.font,
                        NSForegroundColorAttributeName: descLabel.textColor,
                        NSParagraphStyleAttributeName: ps,
                    }];

            [cell.contentView addSubview:descLabel];
            UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
            [NSLayoutConstraint activateConstraints:@[
                [descLabel.topAnchor      constraintEqualToAnchor:m.topAnchor constant:2.0],
                [descLabel.bottomAnchor   constraintEqualToAnchor:m.bottomAnchor constant:-2.0],
                [descLabel.leadingAnchor  constraintEqualToAnchor:m.leadingAnchor],
                [descLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            ]];
            return cell;
        }
        case PackageDetailSectionSettings: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsSummaryCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                              reuseIdentifier:@"SettingsSummaryCell"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            }
            NSDictionary *row = self.settingsSummary[indexPath.row];
            cell.textLabel.text = row[@"title"];
            cell.detailTextLabel.text = row[@"value"];
            return cell;
        }
        case PackageDetailSectionRepoOptions: {
            NSDictionary *param = indexPath.row < (NSInteger)self.repoParams.count
                ? self.repoParams[indexPath.row]
                : @{};
            return [self repoOptionCellForParam:param];
        }
        case PackageDetailSectionAction: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActionCell"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                              reuseIdentifier:@"ActionCell"];
            }
            cell.textLabel.text = [self isDirectToolPackage]
                ? [NSString stringWithFormat:@"打开 %@", self.package.name]
                : [NSString stringWithFormat:@"自定义 %@", self.package.name];
            cell.textLabel.textColor = self.view.tintColor;
            cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
            cell.detailTextLabel.text = [self isDirectToolPackage]
                ? @"选择目标并直接执行操作"
                : @"在「设置」标签页中调整选项";
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            cell.imageView.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
            cell.imageView.tintColor = self.view.tintColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        case PackageDetailSectionCount:
            break;
    }
    return [[UITableViewCell alloc] init];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self sectionAtIndex:indexPath.section] != PackageDetailSectionAction) return;
    if (![self hasSettingsBundle]) return;
    [self navigateToSettingsSection];
}

- (void)navigateToSettingsSection
{
    UITabBarController *tab = self.tabBarController;
    NSUInteger settingsIndex = NSNotFound;
    UINavigationController *settingsNav = nil;
    for (NSUInteger i = 0; i < tab.viewControllers.count; i++) {
        UIViewController *vc = tab.viewControllers[i];
        if ([vc.tabBarItem.title isEqualToString:@"设置"]) {
            settingsIndex = i;
            if ([vc isKindOfClass:UINavigationController.class]) {
                settingsNav = (UINavigationController *)vc;
            }
            break;
        }
    }
    if (settingsIndex == NSNotFound || !settingsNav) return;

    [settingsNav popToRootViewControllerAnimated:NO];
    SettingsViewController *bundle = [[SettingsViewController alloc] initWithUnderlyingSection:self.package.settingsSection
                                                                                   bundleTitle:self.package.name];
    bundle.installerReturnPackageName = self.package.name;
    // This controller lives in the Packages or the Sources stack, so record the
    // tab it was tapped in; the back button returns there.
    bundle.installerReturnTabTitle = self.navigationController.tabBarItem.title;
    [settingsNav pushViewController:bundle animated:NO];
    tab.selectedIndex = settingsIndex;
}

@end
