//
//  PackageCatalog.m
//  Cyanide
//

#import "PackageCatalog.h"
#import "../SettingsViewController.h"
#import "../tweaks/RepoTweaks.h"
#import "../tweaks/experimental_tweaks.h"

@interface Package ()
@property (nonatomic, readwrite, copy) NSString *symbolName;
@property (nonatomic, readwrite, copy) NSString *author;
@end

@implementation PackageCatalog

static NSString *catalog_string_or_empty(id value)
{
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSArray<NSString *> *catalog_repotweaks_urls(NSUserDefaults *d)
{
    id raw = [d objectForKey:@"RepoTweaksURLs"];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    for (id value in (NSArray *)raw) {
        if ([value isKindOfClass:NSString.class]) [urls addObject:value];
    }
    return urls;
}

static NSDictionary *catalog_repotweaks_caches(NSUserDefaults *d)
{
    id raw = [d objectForKey:@"RepoTweaksCaches"];
    return [raw isKindOfClass:NSDictionary.class] ? (NSDictionary *)raw : @{};
}

static BOOL catalog_repo_script_requires_native_bridge(NSString *rawScript)
{
    if (![rawScript isKindOfClass:NSString.class] || rawScript.length == 0) return NO;
    return [rawScript containsString:@"nativeCallBuff"] ||
           [rawScript containsString:@"runOnMainEvaluate"] ||
           [rawScript containsString:@"Native.callSymbol"];
}

+ (NSArray<Package *> *)repoPackages
{
    if (!repotweaks_sources_enabled()) return @[];
    repotweaks_seed_default_repos();

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *caches = catalog_repotweaks_caches(d);
    NSMutableArray<Package *> *packages = [NSMutableArray array];

    for (NSString *url in catalog_repotweaks_urls(d)) {
        id repoRaw = caches[url];
        if (![repoRaw isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *repo = (NSDictionary *)repoRaw;
        NSString *repoName = catalog_string_or_empty(repo[@"repoName"]);
        NSString *author = catalog_string_or_empty(repo[@"author"]);
        id tweaksRaw = repo[@"tweaks"];
        if (![tweaksRaw isKindOfClass:NSArray.class]) continue;

        for (id tweakRaw in (NSArray *)tweaksRaw) {
            if (![tweakRaw isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *tweak = (NSDictionary *)tweakRaw;
            NSString *tweakID = catalog_string_or_empty(tweak[@"id"]);
            NSString *name = catalog_string_or_empty(tweak[@"name"]);
            NSString *scriptURL = catalog_string_or_empty(tweak[@"scriptURL"]);
            if (tweakID.length == 0 || name.length == 0 || scriptURL.length == 0) continue;

            NSString *identifier = [NSString stringWithFormat:@"repo.%@", repotweaks_storage_key(url, tweakID)];
            Package *pkg = [[Package alloc] initRepoTweakWithIdentifier:identifier
                                                                   name:name
                                                       shortDescription:catalog_string_or_empty(tweak[@"description"])
                                                                version:catalog_string_or_empty(tweak[@"version"])
                                                                 author:author
                                                               repoName:repoName
                                                                repoURL:url
                                                            repoTweakID:tweakID
                                                           repoScriptURL:scriptURL];
            NSString *symbol = catalog_string_or_empty(tweak[@"symbol"]);
            if (symbol.length > 0) pkg.symbolName = symbol;
            NSString *tweakAuthor = catalog_string_or_empty(tweak[@"author"]);
            if (tweakAuthor.length > 0) pkg.author = tweakAuthor;
            NSString *rawScript = [d stringForKey:repotweaks_script_defaults_key(url, tweakID)];
            NSString *unsupportedReason = repotweaks_unsupported_reason(tweak);
            if (unsupportedReason.length > 0) {
                pkg.installDisabledReason = unsupportedReason;
                pkg.unstableWarning = unsupportedReason;
            } else if (rawScript.length == 0) {
                pkg.installDisabledReason = @"安装前请先在「源」标签页刷新此源。";
            } else if (pkg.repoTweakUsesQuickLoader && catalog_repo_script_requires_native_bridge(rawScript)) {
                pkg.installDisabledReason = @"这个源插件需要专门的 Cyanide 原生后端才能安装。";
            }
            [packages addObject:pkg];
        }
    }

    return [packages sortedArrayUsingComparator:^NSComparisonResult(Package *a, Package *b) {
        return [a.name caseInsensitiveCompare:b.name];
    }];
}

// Underlying section indices for the detail-mode SettingsViewController push.
// Defined directly from the shared SettingsSection enum (SettingsViewController.h)
// so they track the enum automatically — the previous hand-copied numbers had
// drifted (e.g. kSecLayoutExtras was 15 = SectionSnowBoardLite, so "Customize
// Home Layout Extras" opened the theme selector).
static const NSInteger kSecSBC              = SectionSBC;
static const NSInteger kSecStatBar          = SectionStatBar;
static const NSInteger kSecNSBar            = SectionNSBar;
static const NSInteger kSecNiceBarLite      = SectionNiceBarLite;
static const NSInteger kSecPowercuff        = SectionPowercuff;
static const NSInteger kSecDragCoefficient  = SectionDragCoefficient;
static const NSInteger kSecLayoutExtras     = SectionLayoutExtras;
static const NSInteger kSecNanoRegistry     = SectionNanoRegistry;
static const NSInteger kSecSnowBoardLite    = SectionSnowBoardLite;
static const NSInteger kSecLiveWP           = SectionLiveWP;
static const NSInteger kSecLocationSim      = SectionLocationSim;
static const NSInteger kSecAppSwitcherGrid  = SectionAppSwitcherGrid;
static const NSInteger kSecFloatingDock     = SectionFloatingDock;
static const NSInteger kSecFastLockXLite    = SectionFastLockXLite;
static const NSInteger kSecQuickLoader      = SectionQuickLoader;
static const NSInteger kSecRepoTweaks       = SectionRepoTweaks;
static const NSInteger kSecLockScreenDuration = SectionLockScreenDuration;
static const NSInteger kSecPasscodeTheme    = SectionPasscodeTheme;
static const NSInteger kSecOTA              = SectionOTA;

+ (NSArray<Package *> *)allPackages
{
    NSArray<Package *> *full = [self allPackagesIncludingExperimental];
    BOOL experimentalOn = [[NSUserDefaults standardUserDefaults]
                            boolForKey:kSettingsExperimentalTweaksEnabled];

    NSMutableArray<Package *> *out = [NSMutableArray arrayWithCapacity:full.count];
    for (Package *p in full) {
        if (p.creatorOnly) continue;
        if (p.experimental && !experimentalOn) continue;
        [out addObject:p];
    }
    return out;
}

+ (NSArray<Package *> *)allPackagesIncludingExperimental
{
    static NSArray<Package *> *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *version = @"1.0";
        Package *statBar = [[Package alloc] initWithIdentifier:@"com.darksword.statbar"
                                           name:@"StatBar"
                               shortDescription:@"电池温度与可用内存浮层"
                                longDescription:@"在 SpringBoard 中安装一个浮层窗口，在系统状态栏旁实时显示电池温度与可用内存。刷新间隔可调，你可以用更少的实时刷新换取更长的续航。\n\n单位、显示的指标和刷新速度都在「设置」标签页中配置。"
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"状态栏"
                                     symbolName:@"thermometer.medium"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsStatBarEnabled
                                          isNew:NO];
        statBar.settingsSection = kSecStatBar;

        Package *nsBar = [[Package alloc] initWithIdentifier:@"com.darksword.nsbar"
                                           name:@"NSBar"
                               shortDescription:@"状态栏网速浮层"
                                longDescription:@"以紧凑的 SpringBoard 状态栏浮层实时显示下载与上传速度。可在「设置」中选择它贴在角落还是居中。\n\n移植自 d1y/cyanide-ios。"
                                        version:version
                                         author:@"d1y"
                                       category:@"状态栏"
                                     symbolName:@"network"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsNSBarEnabled
                                          isNew:NO];
        nsBar.settingsSection = kSecNSBar;

        Package *niceBarLite = [[Package alloc] initWithIdentifier:@"com.darksword.nicebarlite"
                                           name:@"NiceBar Lite"
                               shortDescription:@"NiceBar 风格的状态栏标签"
                                longDescription:@"在状态栏周围添加可配置的文字标签。每个位置可以显示自定义文字、日期/时间格式，以及电池、内存、网速、运行时间、IP 地址、磁盘空间、热状态和流量计数等系统数值。\n\n移植自 d1y/cyanide-ios。"
                                        version:version
                                         author:@"d1y"
                                       category:@"状态栏"
                                     symbolName:@"textformat.size"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsNiceBarLiteEnabled
                                          isNew:NO];
        niceBarLite.settingsSection = kSecNiceBarLite;

#if CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE
#endif

        Package *sbc = [[Package alloc] initWithIdentifier:@"com.darksword.sbcustomizer"
                                           name:@"SBCustomizer"
                               shortDescription:@"自定义程序坞、图标网格、应用位置与页面数量"
                                longDescription:@"自定义程序坞的图标数量与主屏幕图标网格（列数与行数）。它可以把选定的应用移动到新空出的程序坞位置，可选择隐藏图标名称，还能为第一页和后续页面分别设置图标容量。\n\n可选的「移入程序坞」默认选中 Watusi 的 WhatsApp 副本；在「设置」中填入其他应用的 bundle identifier 即可更改。"
                                        version:@"1.1"
                                         author:@"zeroxjf / Kolbicz"
                                       category:@"主屏幕"
                                     symbolName:@"square.grid.3x3.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSBCEnabled
                                          isNew:NO];
        sbc.settingsSection = kSecSBC;

        Package *powercuff = [[Package alloc] initWithIdentifier:@"com.darksword.powercuff"
                                           name:@"Powercuff"
                               shortDescription:@"通过热压力降低 CPU/GPU 频率"
                                longDescription:@"通过向 thermalmonitord 施加合成的热压力来降低 CPU 与 GPU 频率。适合对发热敏感的任务，或在负载下延长续航。效果会持续到重启。\n\n「标称」是日常使用的默认档。轻、中、重三档会有意把 CPU 压得更低，所以出现卡顿和应用启动变慢正是它在起作用。这些档位对日常舒适使用来说可能过慢，在老设备上尤其明显。\n\n在「设置」标签页中选择档位。"
                                        version:version
                                         author:@"rpetrich"
                                       category:@"System"
                                     symbolName:@"bolt.slash.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsPowercuffEnabled
                                          isNew:NO];
        powercuff.settingsSection = kSecPowercuff;

        Package *axon = [[Package alloc] initWithIdentifier:@"com.darksword.axonlite"
                                           name:@"Axon Lite"
                               shortDescription:@"按应用归类通知中心的请求"
                                longDescription:@"在 Cyanide 保持 RemoteCall 会话期间，用一个 SpringBoard 浮层把可见的通知中心请求按应用归类，并过滤重复项。\n\n无需额外配置。"
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"SpringBoard"
                                     symbolName:@"bell.badge.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsAxonLiteEnabled
                                          isNew:NO];
        axon.unstableWarning = @"⚠️ 实验性功能：仍在开发中。可能出现 SpringBoard 崩溃、通知丢失、布局错乱，以及在不同 Cyanide 版本之间失效。请勿依赖它处理任何重要事情。";

#if CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE



        Package *stageStrip = [[Package alloc] initWithIdentifier:@"com.darksword.stagestrip"
                                           name:@"Dynamic Stage Lite"
                               shortDescription:@"两个浮动应用窗口，iPad 风格"
                                longDescription:
            @"在 SpringBoard 之上以可调整大小的浮动窗口运行两个应用。\n\n"
            @"基于 tomt000 的 Dynamic Stage —— 最早把「舞台管理器」带到 iPhone 的插件。Dynamic Stage Lite 是一个独立的、仅用 RemoteCall 的重新实现，采用分屏 + 场景托管的思路；没有复用任何原始插件代码或素材。完整版请到 Havoc 查看 tomt000 的作品。\n\n"
            @"使用方法：\n"
            @"• 点按屏幕右下角的小圆点打开选择器。\n"
            @"• 点按两个应用即可并排启动它们。\n"
            @"• 拖动顶部条可移动窗口；拖动任意边角可调整大小。\n"
            @"• 窗口左上角的 X 用于关闭该窗口。\n"
            @"• 选择器托盘里的齿轮可跳回 Cyanide 设置。\n\n"
            @"首次运行会比较慢。选择器需要通过 RemoteCall 枚举所有已安装应用，并为每个应用生成一个图标块 —— 全新安装后大约需要 1 到 2 分钟。再次运行会复用缓存，速度很快。\n\n"
            @"尚不完善之处：\n"
            @"• 尚未接通进入托管应用的触摸事件 —— 窗口只能用于查看和切换，不能滚动或输入。\n"
            @"• 启动全屏应用时自动关闭窗口的功能还没接上；请手动点 X 关闭。\n"
            @"• App 资源库还在填充时，手势可能卡顿。"
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"sidebar.left"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsStageStripEnabled
                                          isNew:NO];
        stageStrip.unstableWarning = @"Beta / 不稳定：首次运行需要 1 到 2 分钟，因为选择器要枚举所有已安装应用并为每个应用生成图标块。再次运行会很快。进入浮动窗口的触摸事件尚未接通，因此在浮动窗口内滚动或输入可能无效。";
#endif

        Package *locationSim = [[Package alloc] initWithIdentifier:@"com.darksword.locationsim"
                                           name:@"Location Simulator"
                               shortDescription:@"CoreLocation 静态坐标模拟"
                                longDescription:@"通过 Apple 的 CLSimulationManager 伪造设备的 GPS 位置。需要先安装并设置好 Apple 地图 —— 地图是驱动该模拟的 RemoteCall 宿主进程。\n\n这是一个手动工具，不是可安装的软件包。打开「控制」，选择目标，然后使用「模拟当前目标」或「恢复真实位置」。每次运行都会打开活动日志，并在请求返回时标记完成。重置可能需要几分钟，并且可能需要重启设备再加上额外等待时间。\n\n「设置」中会显示当前目标以及海拔和精度。v1 仅支持静态坐标；路线回放与替代守护进程宿主将在后续版本加入。\n\n并非所有应用都会遵循模拟位置。使用自家位置校验或额外信号的应用可能会忽略它。\n\n致谢：本功能所基于的 GPS 伪造 RemoteCall/CLSimulationManager 原型由 kolbicz 提供。ezzuldinSt 的 LSpoof 提供了应用侧 CLLocationManager 伪造、选择器、书签与路线模拟的参考。\n\n系统行为警告：模拟位置影响的不只是地图。与位置相关的功能，包括时区、日期/时间行为、天气、自动化、提醒和服务校验，都可能出现异常。请仅在确知后果的情况下使用。\n\n法律与服务条款提示：模拟位置可能根据使用方式违反应用条款、平台规则、游戏规则、网约车或配送政策，或当地法律。请仅在你获得许可的场景下使用。你需要对自己的使用负责，并自行承担应用或还原本插件的风险。"
                                        version:version
                                         author:@"zeroxjf, kolbicz, ezzuldinSt"
                                       category:@"System"
                                     symbolName:@"location.fill"
                                           kind:PackageInstallKindDirectTool
                                     enabledKey:nil
                                          isNew:NO];
        locationSim.settingsSection = kSecLocationSim;
        locationSim.experimental = NO;
        locationSim.unstableWarning = @"Beta：需要先安装并设置好 Apple 地图。它会改变 CoreLocation 当前的模拟状态 —— 可能影响时区、日期/时间以及其他与位置相关的行为。部分应用和服务禁止或能够检测模拟位置。请仅在确知后果的情况下使用。";

        Package *snowboardLite = [[Package alloc] initWithIdentifier:@"com.darksword.snowboardlite"
                                           name:@"SnowBoard Lite"
                               shortDescription:@"本地 SnowBoard 风格图标主题"
                                longDescription:@"把 SnowBoard/IconBundles 主题导入本地库，并通过 Cyanide 的图标替换流程应用所选主题。支持内置的 iOS 6 主题和从本地文件夹导入。\n\nSnowBoard Lite 是 Cyanide 中图标主题的主入口。\n\n移植自 d1y/cyanide-ios。"
                                        version:version
                                         author:@"d1y"
                                       category:@"Theming"
                                     symbolName:@"square.stack.3d.up.fill"
                                          kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSnowBoardLiteEnabled
                                          isNew:NO];
        snowboardLite.settingsSection = kSecSnowBoardLite;
        snowboardLite.unstableWarning = @"预览：应用前请先导入或选择一个 SnowBoard Lite 主题。";

        Package *liveWP = [[Package alloc] initWithIdentifier:@"com.darksword.livewp"
                                           name:@"LiveWP"
                               shortDescription:@"主屏幕与锁定屏幕的视频壁纸"
                                longDescription:@"在 Cyanide 保持 RemoteCall 会话期间，于 SpringBoard 的主屏幕和锁定屏幕窗口背后播放选定的 MP4/MOV/M4V 视频。\n\n移植自 d1y/cyanide-ios。"
                                        version:version
                                         author:@"d1y"
                                       category:@"Theming"
                                     symbolName:@"play.rectangle.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsLiveWPEnabled
                                          isNew:NO];
        liveWP.settingsSection = kSecLiveWP;

        Package *layoutExtras = [[Package alloc] initWithIdentifier:@"com.darksword.layoutextras"
                                           name:@"Home Layout Extras"
                               shortDescription:@"额外的桌面/程序坞边距与逐图标缩放"
                                longDescription:@"为主屏幕图标网格和程序坞增加额外边距，并可放大或缩小图标。会叠加在 SBCustomizer 之上。\n\n在「设置」标签页中可分别调整主屏幕的左/右/上/下边距、程序坞的水平边距，以及桌面/程序坞的图标缩放。默认值与系统一致（无边距、100% 缩放）。\n\n在「运行」时生效；重启 SpringBoard 后不会保留。\n\niOS 18：直接修改 SBIconController 的布局配置（沿用上游 kolbicz 的做法）。\niOS 26：遍历实时的 SBIconListView/SBIconView 层级，逐个调整 frame 与 iconImageInfo（iOS 26 的布局类为只读）。在 iOS 26 上只在「运行」时生效一次 —— 旋转或滑动翻页可能触发 iOS 26 的自动布局重排，若发生请重新运行。"
                                        version:version
                                         author:@"kolbicz"
                                      category:@"主屏幕"
                                     symbolName:@"square.dashed.inset.filled"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsLayoutExtrasEnabled
                                          isNew:NO];
        layoutExtras.settingsSection = kSecLayoutExtras;
        NSInteger iosMajor = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
        if (iosMajor >= 26) {
            layoutExtras.knownIssues = @[
                @"iOS 26：旋转或滑动翻页后布局可能被重置。请重新运行以再次应用。",
            ];
        }

        // Lock Screen Duration is a manual tool (DirectTool): it appears in the
        // tweak list with author/version, but instead of a queued install it
        // opens its own Settings section whose Apply / Remove / Read buttons
        // write the SBMinimumLockscreenIdleTime floor and offer a respring. Like
        // OTA Updates it is not part of the Run queue.
        Package *lockScreenDuration = [[Package alloc] initWithIdentifier:@"com.darksword.lockscreen-duration"
                                           name:@"锁屏时长"
                               shortDescription:@"让锁定屏幕保持更久的亮屏"
                                longDescription:@"延长锁定屏幕自身的「变暗后休眠」计时 —— 也就是你阅读通知时那段让屏幕熄灭的短倒计时，它与「设置 > 自动锁定」是分开的。\n\n这是一个手动工具，不是排队安装的软件包。打开「控制」，设置秒数，然后点按「应用锁屏时长」。它会写入 SpringBoard 偏好设置 SBMinimumLockscreenIdleTime（一个作用于所有锁屏闲置状态的全局下限，Face ID 之后也包含在内），并提供重启 SpringBoard 以使其生效。该值在重启 SpringBoard 和设备后仍然保留。使用「移除」可恢复系统默认时长，或用「读取当前值」查看已配置的数值。\n\n机制：-[SBIdleTimerDescriptorFactory sanitizeDescriptorForLockscreenDefaults:] 会用 max(interval, minimumLockscreenIdleTime) 为每个锁屏间隔取下限。Face ID 注视（注意力感知）可以让屏幕亮得更久。\n\n请先至少运行一次利用链，使内核权限处于可用状态。下次重启 SpringBoard 后生效。"
                                        version:@"1.0"
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
                                     symbolName:@"lock.rectangle.on.rectangle"
                                           kind:PackageInstallKindDirectTool
                                     enabledKey:nil
                                          isNew:YES];
        lockScreenDuration.settingsSection = kSecLockScreenDuration;

        Package *appSwitcherGrid = [[Package alloc] initWithIdentifier:@"com.darksword.appswitchergrid"
                                           name:@"App Switcher Grid"
                               shortDescription:@"网格式应用切换器"
                                longDescription:@"应用一个运行时的 SpringBoard 方法补丁，让应用切换器使用网格/牌堆样式。\n\n不会写入系统文件。重启 SpringBoard 即可恢复系统默认的应用切换器。如果你在「隐藏主屏横条」之后重启了 SpringBoard，需要再次运行 App Switcher Grid，因为重启会清除这个运行时补丁。\n\n移植自 d1y/cyanide-ios。"
                                        version:version
                                         author:@"rooootdev"
                                       category:@"SpringBoard"
                                     symbolName:@"square.grid.2x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsAppSwitcherGridEnabled
                                          isNew:NO];
        appSwitcherGrid.settingsSection = kSecAppSwitcherGrid;
        appSwitcherGrid.unstableWarning = @"Beta：在内存中修补 SpringBoard 的运行时方法。重启 SpringBoard 可恢复默认，但在不受支持的版本上可能导致应用切换器显示异常或 SpringBoard 崩溃。每次重启 SpringBoard 后都需要重新运行。";

        Package *floatingDock = [[Package alloc] initWithIdentifier:@"com.darksword.floatingdock"
                                           name:@"iPad Dock"
                               shortDescription:@"带 App 资源库的 iPad 风格程序坞"
                                longDescription:@"在当前 SpringBoard 会话中，把程序坞变成 SpringBoard 自带的 iPad 风格程序坞，包含 App 资源库按钮。\n\n不会写入系统文件。关闭它即可恢复系统默认程序坞，重启 SpringBoard 也一样。可与「禁用 App 资源库」配合使用：此时 App 资源库只存在于程序坞中。\n\n移植自 hxhlb/cyanide。"
                                        version:version
                                         author:@"Banana"
                                       category:@"SpringBoard"
                                     symbolName:@"dock.rectangle"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsFloatingDockEnabled
                                          isNew:YES];
        floatingDock.settingsSection = kSecFloatingDock;
        floatingDock.unstableWarning = @"使用 SpringBoard 私有的程序坞控制器（仅在内存中）。如果程序坞显示异常，请关闭它或重启 SpringBoard。";

        Package *quickLoader = [[Package alloc] initWithIdentifier:@"com.darksword.quickloader"
                                           name:@"QuickLoader"
                               shortDescription:@"执行自定义 .js 代码"
                                longDescription:@"从「文件」中选择本地 JavaScript 文件，配置声明的参数，然后通过 Cyanide 的 SpringBoard RemoteCall 桥运行它。\n\n请只运行你信任的脚本。JavaScript 插件可以发送 SpringBoard 私有消息，脚本有 bug 时可能导致设备不稳定。"
                                        version:@"1.0"
                                         author:@"Iggy05"
                                       category:@"SpringBoard"
                                     symbolName:@"bolt.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsQuickLoaderEnabled
                                          isNew:NO];
        quickLoader.settingsSection = kSecQuickLoader;
        quickLoader.unstableWarning = @"运行用户选择的 JavaScript，并可使用 Cyanide 的 RemoteCall 辅助函数。请只使用你信任的脚本；有问题的脚本会让 SpringBoard 崩溃。";

#if CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE
        Package *fastLockXLite = [[Package alloc] initWithIdentifier:@"com.darksword.fastlockx-lite"
                                           name:@"FastLockX Lite"
                               shortDescription:@"Face ID 重试与解锁控制"
                                longDescription:@"从 Artem Kasper 的 iOS 15 插件中恢复出的可用 FastLockX 原语，以纯 RemoteCall 方式移植。\n\n致谢：原版 FastLockX 由 Artem Kasper 开发；Cyanide 的 FastLockX Lite 移植由 zeroxjf 完成。\n\n它可以反复触发 SpringBoard 的生物识别重试路径、请求 iOS 26 的生物识别协调器发起 Mesa/Face ID 解锁，并发送原始的锁屏解锁请求作为兜底。通过「应用插件」安装后，这些重试/解锁请求会挂在 SpringBoard 定时器上，因此 Cyanide 关闭后「拿起即解锁」仍可生效。解锁之后触发循环会再次暂停。\n\n使用「停用」「清理」或重启 SpringBoard 可以停止这些定时器。"
                                        version:version
                                         author:@"Artem Kasper / zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"lock.open.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsFastLockXLiteEnabled
                                          isNew:NO];
        fastLockXLite.settingsSection = kSecFastLockXLite;
        fastLockXLite.unstableWarning = @"Beta / 不稳定：会发送 SpringBoard 私有的锁屏与生物识别资源消息。「始终开启」会在设备锁定时运行 SpringBoard 定时器，如果 Face ID 变得频繁或异常，请停用它或重启 SpringBoard。";
#endif

        Package *nanoRegistry = [[Package alloc] initWithIdentifier:@"com.darksword.nanoregistry"
                                           name:@"Watch Pairing Override"
                               shortDescription:@"配对更新的手表，或救活旧手表"
                                longDescription:@"修改这台 iPhone 上保存的 watchOS 配对范围。\n\n大多数人应使用「设置」中的 watchOS 范围 99/23/10/6，然后应用覆盖。这些是配对协议代次，不是 Apple Watch 型号数字。99 提高 watchOS 的配对上限。23 让第 23 代设置协议仍被接受。10 和 6 让旧芯片与多手表的下限保持正常值。\n\n目前 Apple Watch Ultra 3 无法在低于 iOS 26 的版本上配对。\n\n系统文件警告：这会修改本地的 NanoRegistry 兼容性索引 MobileAsset，并在原文件旁保存 .cyanide.bak 备份。配对素材的修改可能失败、只部分生效、需要重启 SpringBoard 或重启设备才能稳定，或导致配对状态不一致。应用或移除本覆盖的风险由你自行承担。\n\n安装或移除覆盖后，请重启 SpringBoard 或重启设备，再尝试配对。"
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"System"
                                     symbolName:@"applewatch.radiowaves.left.and.right"
                                           kind:PackageInstallKindNanoRegistry
                                     enabledKey:nil
                                          isNew:NO];
        nanoRegistry.settingsSection = kSecNanoRegistry;
        nanoRegistry.unstableWarning = @"警告：会修改本地的 NanoRegistry MobileAsset。Cyanide 会在原文件旁保存 .cyanide.bak 备份，但系统文件的修改仍可能失败，或需要重启 SpringBoard / 重启设备。应用或移除本覆盖的风险由你自行承担。";

        Package *callRecordingSound = [[Package alloc] initWithIdentifier:@"com.darksword.callrecording-sound"
                                           name:@"Call Recording Sound"
                               shortDescription:@"静音通话录音的开始/结束提示音"
                                longDescription:@"用 Cyanide 内置的静音音频替换 CallServices 的 StartDisclosureWithTone 与 StopDisclosure 音频文件。\n\n致谢：YangJiiii（@duongduong0908）提供了 EnsWilde 与 Disable Call Recording 这两个 BookRestore 参考工具。原始项目将「禁用通话录音」这一概念归功于 @Little_34306。Cyanide 的移植、基于 KRW 的实现以及生成的替代静音音频素材由 zeroxjf 完成。\n\n系统文件警告：这会修改 /var/mobile/Library/CallServices/Greetings/default 下的文件。Cyanide 会把最初的原始文件备份到自己的应用容器中，但系统文件替换仍可能失败、只部分生效，或需要重启 SpringBoard / 重启设备才能稳定。\n\n法律提示：通话录音提示音在某些地区可能是为满足知情同意、告知或隐私法要求而存在的。你有责任了解并遵守适用于你的法律。\n\n本移植不使用旧的 Books/BookRestore/sparserestore 路径。Cyanide 会运行 KRW，解锁本地 /private/var 的写权限，然后直接写入 CallServices 文件。\n\n使用「恢复原始音频」可以把 Cyanide 的备份写回（若存在）。应用或还原本插件的风险由你自行承担。"
                                        version:version
                                         author:@"YangJiiii (@duongduong0908) / zeroxjf"
                                       category:@"System"
                                     symbolName:@"speaker.slash.fill"
                                           kind:PackageInstallKindCallRecordingSound
                                     enabledKey:nil
                                          isNew:NO];
        callRecordingSound.experimental = NO;
        callRecordingSound.unstableWarning = @"Beta：对 CallServices 系统文件的持久替换。在你所在的地区，提示音可能是法律要求的；你需要对自己的使用负责，并自行承担应用风险。如果希望把 Cyanide 的备份写回，请在移除 Cyanide 之前先使用「恢复原始音频」。";

        Package *passcodeTheme = [[Package alloc] initWithIdentifier:@"com.darksword.passcode-theme"
                                           name:@"密码样式"
                               shortDescription:@"自定义锁定屏幕密码键盘图案"
                                longDescription:@"用你在「密码样式」面板中导入或制作的样式，替换 /var/mobile/Library/Caches/TelephonyUI-* 下的锁屏密码键盘图案。一个样式可以只覆盖部分数字，其余保持系统默认。\n\n打开「控制」可应用它或还原已保存的原始文件。锁定再解锁（或重启 SpringBoard）即可看到变化。\n\n系统文件警告：Cyanide 保存的原始文件位于它自己的应用容器内，因此重装 Cyanide 会把它们一起删掉 —— 如果你打算重装，请先从「密码样式」面板导出。\n\n致谢：移植自 ruter 与 neonmodder123 为 Lara 制作的 Passcode 实现，并由 leonardob8777-bit 在 Eagle 中继承与扩展（https://github.com/leonardob8777-bit/Eagle，AGPL-3.0）。Cyanide 移植由 FleetingDreamso 完成。"
                                        version:version
                                         author:@"ruter / neonmodder123 / leonardob8777-bit / FleetingDreamso"
                                       category:@"Theming"
                                     symbolName:@"circle.grid.3x3.fill"
                                           kind:PackageInstallKindDirectTool
                                     enabledKey:nil
                                          isNew:YES];
        passcodeTheme.settingsSection = kSecPasscodeTheme;
        passcodeTheme.unstableWarning = @"警告：会重写锁定屏幕使用的系统键盘图案。Cyanide 会校验每次写入，但修改仍可能失败或只部分生效。「还原原始数字」可以把已保存的原始文件写回。";

        Package *hideHomeBar = [[Package alloc] initWithIdentifier:@"com.darksword.hide-home-bar"
                                           name:@"隐藏主屏横条"
                               shortDescription:@"隐藏底部的 Home 指示条"
                                longDescription:@"使用 Cyanide 稳定的文件页清零路径，把 /System/Library/PrivateFrameworks/MaterialKit.framework/Assets.car 的第一页清零；SpringBoard 重新加载素材后，底部的 Home 指示条就会被隐藏。\n\n请单独运行「隐藏主屏横条」，然后重启 SpringBoard 让素材缓存刷新。要恢复 Home 指示条，选择「恢复主屏横条」并再次重启 SpringBoard。其他运行时 SpringBoard 插件（例如 App Switcher Grid）应在重启之后单独运行应用。\n\n致谢：Home 横条素材定位来自 C4ndyF1sh/ZeroCalories，原始的文件页清零思路来自 jailbreakdotparty/dirtyZero。Cyanide 移植由 zeroxjf 完成。"
                                        version:version
                                         author:@"C4ndyF1sh / jailbreakdotparty / zeroxjf"
                                       category:@"主屏幕"
                                     symbolName:@"line.3.horizontal"
                                           kind:PackageInstallKindHideHomeBar
                                     enabledKey:nil
                                          isNew:NO];
        hideHomeBar.unstableWarning = @"Beta：对系统素材做文件页清零。请单独运行，隐藏后重启 SpringBoard。要恢复 Home 指示条，选择「恢复主屏横条」并重启 SpringBoard。";

        // Manual tool (DirectTool), same shape as Lock Screen Duration: the
        // detail view offers Open Controls, which opens the OTA Updates
        // section in Settings where Disable / Enable / Read Current Status
        // act immediately. It was a queued Disable/Enable menu before, which
        // routed a one-tap system-file edit through the install queue for no
        // benefit and split the read button off into Settings on its own.
        Package *otaBlock = [[Package alloc] initWithIdentifier:@"com.darksword.ota-block"
                                           name:@"OTA 更新"
                               shortDescription:@"开启或关闭 OTA 系统更新"
                                longDescription:@"通过编辑 disabled.plist 停用或启用负责 OTA 系统更新的 launchd 作业。状态在重启后仍然保留。\n\n系统文件警告：这会编辑 /private/var/db/com.apple.xpc.launchd/disabled.plist。写入错误或不完整可能影响重启后的 launchd 作业状态。开启或关闭 OTA 更新的风险由你自行承担。\n\n这是一个手动工具，不是排队安装的软件包。打开「控制」，点按「停用 OTA 更新」以阻止更新，或点按「启用 OTA 更新」以恢复；改动会立即写入，没有「运行」或「应用」步骤。「读取当前状态」会报告更新守护进程当前是否被阻止。\n\n请先至少运行一次利用链，使内核权限处于可用状态 —— 「读取当前状态」不会自己启动它。\n\n1.2 版把控制项移到了「设置」中；1.1 版新增了「读取当前状态」。"
                                        version:@"1.2"
                                         author:@"kolbicz"
                                       category:@"System"
                                     symbolName:@"icloud.slash.fill"
                                          kind:PackageInstallKindDirectTool
                                    enabledKey:nil
                                         isNew:NO];
        otaBlock.settingsSection = kSecOTA;
        otaBlock.unstableWarning = @"警告：持久性系统文件修改。此软件包会修改 launchd 的 disabled.plist，从而在重启后改变 OTA 作业状态。开启或关闭 OTA 更新的风险由你自行承担。";

        Package *disableAppLibrary = [[Package alloc] initWithIdentifier:@"com.darksword.disable-app-library"
                                           name:@"Disable App Library"
                               shortDescription:@"移除 App 资源库页面"
                                longDescription:@"移除位于主屏幕最后一页之后的 App 资源库页面。滑过最后一页将不再有反应。\n\n适用于 iOS 17 及更高版本。"
                                        version:@"1.1"
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
                                     symbolName:@"square.grid.2x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDisableAppLibrary
                                          isNew:NO];

        list = @[
            statBar,
            nsBar,
            niceBarLite,
            sbc,
            layoutExtras,
            powercuff,

            disableAppLibrary,

            [[Package alloc] initWithIdentifier:@"com.darksword.disable-icon-flyin"
                                           name:@"Disable Icon Fly-In"
                               shortDescription:@"跳过图标弹入动画"
                                longDescription:@"跳过解锁或切换应用后主屏幕图标出现时的弹入动画。图标会直接出现在最终位置。"
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
                                     symbolName:@"sparkles"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDisableIconFlyIn
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.lara.springboard-tools"
                                           name:@"SpringBoard 工具"
                               shortDescription:@"你的程序坞、文件夹与控制中心外观"
                                longDescription:@"把 设置 → Lara → SpringBoard 工具 中设定的外观（程序坞、文件夹、控制中心、通知、应用切换器）与其他插件一起应用，这样重启 SpringBoard 后点一次「应用插件」就能恢复。"
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
                                     symbolName:@"dock.rectangle"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSBToolsWithTweaks
                                          isNew:YES],

            [[Package alloc] initWithIdentifier:@"com.darksword.hide-new-app-dots"
                                           name:@"Hide New App Dots"
                               shortDescription:@"新装或更新的应用旁不再显示蓝点"
                                longDescription:@"移除 iOS 在新安装和最近更新的应用名称旁显示的蓝点，并在下次重启 SpringBoard 之前不再出现新的蓝点。"
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
                                     symbolName:@"circle.slash"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSHideNewAppDots
                                          isNew:YES],

            [[Package alloc] initWithIdentifier:@"com.darksword.zero-wake-animation"
                                           name:@"Zero Wake Animation"
                               shortDescription:@"唤醒时瞬间亮屏"
                                longDescription:@"移除唤醒屏幕时的淡入动画。屏幕会立即以全亮度亮起。"
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
                                     symbolName:@"moon.zzz.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSZeroWakeAnimation
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.zero-backlight-fade"
                                           name:@"Zero Backlight Fade"
                               shortDescription:@"锁定/解锁背光瞬间切换"
                                longDescription:@"把背光渐变时长归零，使锁定与解锁时屏幕立即点亮或熄灭。"
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
                                     symbolName:@"sun.max.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSZeroBacklightFade
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.double-tap-to-lock"
                                           name:@"Double-Tap to Lock"
                               shortDescription:@"双击壁纸锁定设备"
                                longDescription:@"双击主屏幕或锁定屏幕背景的空白区域即可锁定设备。1.1 版排除了图标与密码输入界面，修复了打开应用或输入密码时误锁的问题。"
                                        version:@"1.1"
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
                                     symbolName:@"hand.tap.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDoubleTapToLock
                                          isNew:NO],

            ({
                Package *drag = [[Package alloc] initWithIdentifier:@"com.darksword.drag-coefficient"
                                                               name:@"Drag Coefficient"
                                                   shortDescription:@"自定义 SpringBoard 动画速度倍率"
                                                    longDescription:@"覆盖 SpringBoard 中的 _UIAnimationDragCoefficient，让所有 UIKit 弹簧动画变快或变慢。\n\n在「动效速度系数」设置面板中设定系数。50% = 0.50×（快 2 倍），25% = 0.25×（快 4 倍），100% = 系统默认。\n\n来自 kolbicz/DarkSword-Tweaks。"
                                                            version:@"1.1"
                                                             author:@"kolbicz"
                                                           category:@"SpringBoard"
                                                         symbolName:@"dial.medium.fill"
                                                               kind:PackageInstallKindToggle
                                                         enabledKey:kSettingsDSDragCoefficientEnabled
                                                              isNew:NO];
                drag.settingsSection = kSecDragCoefficient;
                drag;
            }),

            otaBlock,
            lockScreenDuration,

            // Higher-risk/manual packages last so their warnings sit below core tweaks.
#if CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE
#endif
            axon,
            nanoRegistry,
            callRecordingSound,
            passcodeTheme,
            hideHomeBar,
#if CYANIDE_EXPERIMENTAL_TWEAKS_AVAILABLE
            stageStrip,
            fastLockXLite,
#endif
            locationSim,
            snowboardLite,
            liveWP,
            appSwitcherGrid,
            floatingDock,
            quickLoader,
        ];
    });
    NSArray<Package *> *repoPackages = [self repoPackages];
    if (repoPackages.count == 0) return list;
    return [list arrayByAddingObjectsFromArray:repoPackages];
}

+ (NSArray<NSString *> *)categoriesInOrder
{
    NSArray<NSString *> *preferred = @[
        @"开发中",
        @"Beta",
        @"Experimental",
        @"状态栏",
        @"主屏幕",
        @"Theming",
        @"SpringBoard",
        @"System",
        @"JavaScript 插件",
    ];
    NSMutableArray<NSString *> *all = [NSMutableArray array];
    for (Package *p in [self allPackages]) {
        if (![all containsObject:p.category]) [all addObject:p.category];
    }
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSString *cat in preferred) {
        if ([all containsObject:cat]) [order addObject:cat];
    }
    for (NSString *cat in all) {
        if (![order containsObject:cat]) [order addObject:cat];
    }
    return order;
}

+ (NSDictionary<NSString *, NSArray<Package *> *> *)packagesByCategory
{
    NSMutableDictionary<NSString *, NSMutableArray<Package *> *> *buckets = [NSMutableDictionary dictionary];
    for (Package *p in [self allPackages]) {
        NSMutableArray<Package *> *bucket = buckets[p.category];
        if (!bucket) {
            bucket = [NSMutableArray array];
            buckets[p.category] = bucket;
        }
        [bucket addObject:p];
    }
    return buckets;
}

@end
