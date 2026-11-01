//
//  LaraViewController.m
//  Cyanide
//
//  Settings → Lara: tools ported from lara by rooootdev
//  (https://github.com/rooootdev/lara), with his permission. The SpringBoard
//  work lives in tweaks/lara_tools.m; this screen only drives it.
//

#import "LaraViewController.h"
#import "SettingsViewController.h"
#import "tweaks/lara_tools.h"
#import "tweaks/app_decrypt.h"
#import "tweaks/sb_materials.h"
#import "tweaks/font_overwrite.h"
#import "FileBrowserViewController.h"
#import "LogTextView.h"
#import <errno.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString * const kLaraCredit = @"移植自 rooootdev 的 lara。";

typedef struct { int mode; const char *title; } LaraHUDMode;
static const LaraHUDMode kLaraHUDModes[] = {
    { -1, "Off" }, { 0, "Basic" }, { 1, "Backdrops" }, { 2, "Particles" }, { 3, "Full" },
    { 5, "Power" }, { 7, "EDR" }, { 8, "Glitches" }, { 9, "GPU Time" }, { 10, "Memory Bandwidth" },
};
static const NSInteger kLaraHUDModeCount = sizeof(kLaraHUDModes) / sizeof(kLaraHUDModes[0]);

@interface LaraViewController () <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic) LaraTool tool;
@property (nonatomic) BOOL busy;
@property (nonatomic, copy) NSString *status;        // shown in the first footer
@property (nonatomic) int hudMode;                   // -1 off, -2 unknown
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *prefStates;   // index -> 0/1
@property (nonatomic, copy) NSArray<NSDictionary *> *jitApps;   // nil until listed (JIT / app limit / cards)
@property (nonatomic, strong) NSDictionary *pickingCard;          // card whose image is being picked
@property (nonatomic, strong) UIProgressView *progressBar;        // under the navigation bar while decrypting
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *sbConfig;   // SpringBoard Tools choices
@property (nonatomic, copy) NSArray<NSString *> *fonts;          // Font Overwrite: imported fonts
@end

@implementation LaraViewController

- (instancetype)initWithTool:(LaraTool)tool
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _tool = tool;
        _hudMode = -2;
        _prefStates = [NSMutableDictionary dictionary];
        switch (tool) {
            case LaraToolPerformanceHUD: self.title = @"性能 HUD"; break;
            case LaraToolDebugOverlay:   self.title = @"调试浮层"; break;
            case LaraToolUpsideDown:     self.title = @"倒置屏幕"; break;
            case LaraToolHiddenSettings: self.title = @"隐藏设置"; break;
            case LaraToolJIT:            self.title = @"JIT 开启器"; break;
            case LaraToolAppLimit:       self.title = @"3 应用限制"; break;
            case LaraToolCards:          self.title = @"钱包卡片图案"; break;
            case LaraToolDecrypt:        self.title = @"应用解密"; break;
            case LaraToolSpringBoard:    self.title = @"SpringBoard 工具"; break;
            case LaraToolFonts:          self.title = @"字体替换"; break;
        }
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    if (self.tool == LaraToolPerformanceHUD || self.tool == LaraToolHiddenSettings) [self readState];
    if (self.tool == LaraToolJIT || self.tool == LaraToolAppLimit || self.tool == LaraToolCards ||
        self.tool == LaraToolDecrypt) [self listJITApps];
    if (self.tool == LaraToolFonts) self.fonts = fontow_imported_fonts();
}

#pragma mark Font Overwrite

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return self.tool == LaraToolFonts && indexPath.section == 0 && indexPath.row < (NSInteger)self.fonts.count;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
 forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete || ![self tableView:tableView canEditRowAtIndexPath:indexPath]) return;
    [NSFileManager.defaultManager removeItemAtPath:self.fonts[indexPath.row] error:nil];
    self.fonts = fontow_imported_fonts();
    [tableView reloadData];
}

- (void)fontsImport
{
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFont ] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (self.tool != LaraToolFonts) return;
    NSString *error = nil;
    for (NSURL *url in urls) fontow_import(url, &error);
    self.fonts = fontow_imported_fonts();
    self.status = error;
    [self.tableView reloadData];
}

- (void)fontsChooseTargetFor:(NSString *)fontPath at:(NSIndexPath *)indexPath
{
    unsigned long long fontSize = [NSFileManager.defaultManager attributesOfItemAtPath:fontPath error:nil].fileSize;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:fontPath.lastPathComponent
        message:[NSString stringWithFormat:@"%@。要替换哪个系统字体？替换字体的体积必须相同或更小。",
                 [NSByteCountFormatter stringFromByteCount:(long long)fontSize countStyle:NSByteCountFormatterCountStyleFile]]
        preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (FontOWTarget t = 0; t < FontOWTargetCount; t++) {
        unsigned long long max = fontow_target_size(t);
        if (!max) continue;
        NSString *title = [NSString stringWithFormat:@"%@（最大 %@）", fontow_target_title(t),
                           [NSByteCountFormatter stringFromByteCount:(long long)max countStyle:NSByteCountFormatterCountStyleFile]];
        UIAlertAction *a = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [weakSelf fontsRun:YES target:t font:fontPath];
        }];
        a.enabled = fontSize <= max;
        [sheet addAction:a];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)fontsRun:(BOOL)apply target:(FontOWTarget)target font:(NSString *)fontPath
{
    __block NSString *outcome = nil;
    __weak typeof(self) weakSelf = self;
    [self runNamed:apply ? @"正在替换字体" : @"正在还原字体"
              work:^BOOL{ return apply ? fontow_apply(target, fontPath, &outcome) : fontow_restore(target, &outcome); }
              done:^(BOOL ok) {
        typeof(self) me = weakSelf;
        if (!me) return;
        me.status = outcome ?: (ok ? nil : @"没有成功。请查看日志。");
        if (ok && me.view.window)
            settings_present_respring_prompt(me, @"现在重启 SpringBoard？",
                [NSString stringWithFormat:@"重启 SpringBoard 后会重新加载 %@。如果之后仍然持续崩溃，请强制重启设备：原字体会恢复。",
                 fontow_target_title(target).lowercaseString]);
    }];
}

// Apps signed with get-task-allow; needs the filesystem sandbox lifted.
- (void)listJITApps
{
    if (self.busy) return;
    self.busy = YES;
    self.status = @"正在查找应用…";
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    settings_unlock_filesystem_async(NO, ^(BOOL ok, NSString *message) {
        typeof(self) me = weakSelf;
        if (!me) return;
        if (!ok) {
            me.busy = NO;
            BOOL needsRun = [message isEqualToString:kSettingsFullExploitRequiredMessage];
            me.status = needsRun ? kSettingsNoKernelAccessHint : (message ?: @"文件系统访问不可用。");
            [me.tableView reloadData];
            if (needsRun) settings_tool_needs_exploit(me, me.tableView, @"JIT 开启器", ^{ [weakSelf listJITApps]; });
            return;
        }
        BOOL limit = me.tool == LaraToolAppLimit, cards = me.tool == LaraToolCards, decrypt = me.tool == LaraToolDecrypt;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *apps = decrypt ? app_decrypt_store_apps() : cards ? lara_wallet_cards()
                          : limit ? lara_sideloaded_apps() : lara_jit_candidate_apps();
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) me2 = weakSelf;
                if (!me2) return;
                me2.busy = NO;
                me2.jitApps = apps;
                // Keep a result message set while the list reloaded.
                BOOL placeholder = [me2.status isEqualToString:@"正在查找应用…"];
                me2.status = apps.count ? (placeholder ? nil : me2.status)
                    : decrypt ? @"没有找到 App Store 应用。"
                    : cards ? @"钱包中没有找到卡片。"
                    : limit ? @"没有找到侧载应用。"
                    : @"这里的应用都无法获得 JIT。只有用开发描述文件（get-task-allow）安装的应用才行，例如用开发者证书侧载的应用。";
                [me2.tableView reloadData];
            });
        });
    });
}

#pragma mark Running

// Runs `work` in SpringBoard; handles busy state, the kernel-access popup and
// errors the same way for every Lara tool.
- (void)runNamed:(NSString *)name work:(BOOL (^)(void))work done:(void (^)(BOOL ok))done
{
    if (self.busy) return;
    self.busy = YES;
    self.status = [name stringByAppendingString:@"…"];
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    settings_springboard_tool_async("Lara", work, ^(BOOL ok, NSString *message) {
        typeof(self) me = weakSelf;
        if (!me) return;
        me.busy = NO;
        if ([message isEqualToString:kSettingsFullExploitRequiredMessage]) {
            me.status = kSettingsNoKernelAccessHint;
            [me.tableView reloadData];
            settings_tool_needs_exploit(me, me.tableView, @"Lara", ^{
                [weakSelf runNamed:name work:work done:done];
            });
            return;
        }
        me.status = ok ? nil : (message ?: @"没有成功。请查看日志。");
        if (done) done(ok);
        [me.tableView reloadData];
    });
}

- (void)readState
{
    __weak typeof(self) weakSelf = self;
    if (self.tool == LaraToolPerformanceHUD) {
        __block int mode = -2;
        [self runNamed:@"Reading" work:^BOOL{
            mode = lara_perf_hud_get_in_session();
            return mode != -2;
        } done:^(BOOL ok) { weakSelf.hudMode = mode; }];
        return;
    }
    NSMutableDictionary *states = [NSMutableDictionary dictionary];
    [self runNamed:@"Reading" work:^BOOL{
        const LaraPrefToggle *t = lara_pref_toggles();
        for (NSInteger i = 0; t[i].title; i++) {
            int v = lara_pref_get_in_session(&t[i]);
            if (v >= 0) states[@(i)] = @(v);
        }
        return YES;
    } done:^(BOOL ok) { [weakSelf.prefStates setDictionary:states]; }];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (self.tool == LaraToolFonts) return 2;   // your fonts, system fonts
    // App limit: action, then the apps. Decrypt: finished IPAs, then the apps.
    if (self.tool == LaraToolSpringBoard) return 1 + (NSInteger)[self sbItemCount];   // Apply/Reset, then one per item
    return (self.tool == LaraToolAppLimit || self.tool == LaraToolDecrypt) ? 2 : 1;
}

#pragma mark SpringBoard Tools

- (NSUInteger)sbItemCount
{
    NSUInteger n = 0;
    for (const SBMatItem *item = sbmat_items(); item->key; item++) n++;
    return n;
}

// Item for a table section (section 0 holds Apply and Reset).
- (const SBMatItem *)sbItemForSection:(NSInteger)section
{
    return section >= 1 && (NSUInteger)section <= [self sbItemCount] ? &sbmat_items()[section - 1] : NULL;
}

- (NSMutableDictionary<NSString *, NSDictionary *> *)sbConfig
{
    if (!_sbConfig) {
        NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:kSBMatConfigKey];
        _sbConfig = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    }
    return _sbConfig;
}

- (NSDictionary *)sbChoiceFor:(const SBMatItem *)item
{
    NSDictionary *c = self.sbConfig[@(item->key)];
    return [c isKindOfClass:NSDictionary.class] ? c : @{};
}

- (void)sbSet:(id)value forKey:(NSString *)key item:(const SBMatItem *)item
{
    NSMutableDictionary *c = [[self sbChoiceFor:item] mutableCopy];
    c[key] = value;
    self.sbConfig[@(item->key)] = c;
    [NSUserDefaults.standardUserDefaults setObject:self.sbConfig forKey:kSBMatConfigKey];
    settings_sbtools_note(NO);   // due again with the tweaks
}

- (void)sbWithTweaksChanged:(UISwitch *)sw
{
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:kSettingsSBToolsWithTweaks];
    if (sw.on) settings_mark_tweak_needs_apply(kSettingsSBToolsWithTweaks);
    settings_sbtools_note(NO);
}

- (UIColor *)sbColorFor:(const SBMatItem *)item
{
    NSArray<NSNumber *> *rgba = [self sbChoiceFor:item][@"color"];
    if (![rgba isKindOfClass:NSArray.class] || rgba.count < 4) return [UIColor colorWithWhite:0 alpha:0.5];
    return [UIColor colorWithRed:rgba[0].doubleValue green:rgba[1].doubleValue blue:rgba[2].doubleValue alpha:rgba[3].doubleValue];
}

- (double)sbBlurFor:(const SBMatItem *)item
{
    NSNumber *blur = [self sbChoiceFor:item][@"blur"];
    return blur ? blur.doubleValue : item->defaultBlur;
}

- (void)sbModeChanged:(UISegmentedControl *)seg
{
    const SBMatItem *item = [self sbItemForSection:seg.tag];
    if (!item) return;
    [self sbSet:@(seg.selectedSegmentIndex) forKey:@"mode" item:item];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:seg.tag] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)sbColorChanged:(UIColorWell *)well
{
    const SBMatItem *item = [self sbItemForSection:well.tag];
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (!item || ![well.selectedColor getRed:&r green:&g blue:&b alpha:&a]) return;
    // Extended sRGB: P3 colors come back below 0 or above 1; CoreMaterial
    // only takes 0…1 (sbmat clamps too).
    CGFloat (^unit)(CGFloat) = ^CGFloat(CGFloat v) { return MIN(MAX(v, 0), 1); };
    [self sbSet:@[ @(unit(r)), @(unit(g)), @(unit(b)), @(unit(a)) ] forKey:@"color" item:item];
}

- (void)sbBlurChanged:(UISlider *)slider
{
    const SBMatItem *item = [self sbItemForSection:slider.tag];
    if (!item) return;
    double blur = round(slider.value);
    [self sbSet:@(blur) forKey:@"blur" item:item];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:slider.tag]];
    UIListContentConfiguration *c = (UIListContentConfiguration *)cell.contentConfiguration;
    if ([c isKindOfClass:UIListContentConfiguration.class]) {
        c.secondaryText = [NSString stringWithFormat:@"%.0f", blur];
        cell.contentConfiguration = c;
    }
}

- (void)sbApply
{
    NSDictionary *config = [self.sbConfig copy];
    __block NSString *why = nil;
    __weak typeof(self) weakSelf = self;
    [self runNamed:@"Applying" work:^BOOL{ return sbmat_apply_in_session(config, &why); }
              done:^(BOOL ok) {
        weakSelf.status = ok ? @"已应用。打开文件夹、控制中心或应用切换器可以看到其余效果。"
                             : (why ?: @"没有成功。请查看日志。");
        if (ok) settings_sbtools_note(YES);
    }];
}

- (NSUInteger)markedAppCount
{
    NSUInteger n = 0;
    for (NSDictionary *app in self.jitApps) if ([app[@"marked"] intValue] == 1) n++;
    return n;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (self.tool == LaraToolAppLimit) return section == 0 ? (self.jitApps ? 1 : 0) : (NSInteger)self.jitApps.count;
    if (self.tool == LaraToolDecrypt) return section == 0 ? 1 : (NSInteger)self.jitApps.count;
    switch (self.tool) {
        case LaraToolPerformanceHUD: return kLaraHUDModeCount;
        case LaraToolDebugOverlay:
        case LaraToolUpsideDown:     return 1;
        case LaraToolFonts:          return section == 0 ? (NSInteger)self.fonts.count + 1 : FontOWTargetCount;
        case LaraToolSpringBoard: {
            if (section == 0) return 3;   // Apply, Reset All, Apply with Tweaks
            const SBMatItem *item = [self sbItemForSection:section];
            return item && [[self sbChoiceFor:item][@"mode"] integerValue] == SBMatModeColor ? 3 : 1;   // mode, tint, blur
        }
        case LaraToolHiddenSettings: {
            NSInteger n = 0;
            for (const LaraPrefToggle *t = lara_pref_toggles(); t->title; t++) n++;
            return n;
        }
        case LaraToolJIT: return (NSInteger)self.jitApps.count;
        case LaraToolAppLimit: return 0;
        case LaraToolCards: return (NSInteger)self.jitApps.count;
        case LaraToolDecrypt: return 0;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (self.tool == LaraToolFonts) return section == 0 ? @"你的字体" : @"系统字体";
    if (self.tool == LaraToolSpringBoard) {
        const SBMatItem *item = [self sbItemForSection:section];
        return item ? @(item->title) : nil;
    }
    if (section != 1 || !self.jitApps.count) return nil;
    if (self.tool == LaraToolAppLimit) return @"侧载应用";
    if (self.tool == LaraToolDecrypt) return @"App Store 应用";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section != [self numberOfSectionsInTableView:tableView] - 1) return nil;
    NSString *about = nil;
    switch (self.tool) {
        case LaraToolPerformanceHUD:
            about = @"Core Animation 的帧率与 GPU 浮层。会一直显示，直到你关闭它或重启设备。";
            break;
        case LaraToolDebugOverlay:
            about = @"Apple 内部的 UIKit 检查器。启用后双击状态栏即可打开。持续到下次重启 SpringBoard。";
            break;
        case LaraToolUpsideDown:
            about = @"允许主屏幕与锁定屏幕旋转到倒置竖屏。持续到下次重启 SpringBoard。";
            break;
        case LaraToolHiddenSettings:
            about = @"隐藏的 iOS 偏好设置。多数项在重启 SpringBoard 后生效，并会一直保留到你关闭。";
            break;
        case LaraToolDecrypt:
            about = @"在本机为 App Store 应用生成解密的 IPA，例如用来注入插件后再侧载。应用会在后台启动，并从其内存中读取解密后的代码；应用扩展独立运行，不包含在内。IPA 会留在本机（Documents/Decrypted），直到你分享出去。请仅对你自己拥有的应用使用；在你所在的地区，移除复制保护可能受到限制。";
            break;
        case LaraToolCards:
            about = @"把钱包中某张卡片的图片换成你自己的（仅外观）。原始图片会先备份，可以还原。重启 SpringBoard 或重新打开钱包即可看到变化。";
            break;
        case LaraToolAppLimit:
            about = @"使用免费 Apple ID 时，iOS 只允许 3 个侧载应用：installd 会给每个应用打标记，只有被标记的应用才计入限制。移除标记即可释放名额。安装或刷新（重新签名）应用后会再次被打上标记，届时再运行一次即可。";
            break;
        case LaraToolSpringBoard:
            about = @"更改程序坞、文件夹、控制中心、通知横幅和应用切换器背后的材质：Apple 原生（可见）、你自己的色调与模糊（着色），或完全移除（禁用）。修改后请点按「应用」。它只作用于 SpringBoard 的内存，重启 SpringBoard 就会失效：重启后再应用一次。\n\n通知横幅：在锁定屏幕上，iOS 会把通知画成一整块模糊再裁成圆角形状。选择「着色」后，它们会脱离这块模糊而显示为直角（配合 lara 的文件也一样）；其他位置的横幅仍保持圆角。\n\n控制中心模糊：选择「着色」后，控制中心关闭时会短暂露出它自带的未着色模糊，iOS 是单独对其做淡出的。";
            break;
        case LaraToolFonts:
            about = @"在内存中替换系统字体：密封的系统卷上不会有任何改动，重启一定恢复原字体；「还原」可以不重启就恢复（会先备份原字体）。从「文件」中导入 .ttf、.otf 或 .ttc，点按它并选择要替换的字体；新字体体积必须相同或更小。普通字体会先适配设备上的系统字体（字重与名称，与 lara 的字体修补器一致；若需要缩放则会丢弃字距）。使用 PostScript（CFF）轮廓的字体无法适配。锁定屏幕时钟会一次性更改所有时钟样式；字重滑块对新字体无效。如果重启 SpringBoard 后仍持续崩溃，请强制重启设备。";
            break;
        case LaraToolJIT:
            about = @"点按应用即可用 JIT 打开它（适用于模拟器等应用）。只有用开发描述文件签名的应用才能获得。JIT 会持续到应用退出；有些应用无法察觉它已开启。";
            break;
    }
    NSMutableArray *parts = [NSMutableArray array];
    if (self.status) [parts addObject:self.status];
    [parts addObject:about];
    [parts addObject:kLaraCredit];
    return [parts componentsJoinedByString:@"\n\n"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *c = [UIListContentConfiguration subtitleCellConfiguration];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    switch (self.tool) {
        case LaraToolPerformanceHUD: {
            LaraHUDMode m = kLaraHUDModes[indexPath.row];
            c.text = [NSString stringWithUTF8String:m.title];
            if (m.mode == self.hudMode) cell.accessoryType = UITableViewCellAccessoryCheckmark;
            break;
        }
        case LaraToolDebugOverlay:
            c.text = @"启用调试浮层";
            c.textProperties.color = self.busy ? UIColor.secondaryLabelColor : UIColor.systemBlueColor;
            break;
        case LaraToolUpsideDown:
            c.text = @"启用倒置屏幕";
            c.textProperties.color = self.busy ? UIColor.secondaryLabelColor : UIColor.systemBlueColor;
            break;
        case LaraToolFonts: {
            if (indexPath.section == 0 && indexPath.row == (NSInteger)self.fonts.count) {
                c.text = @"导入字体…";
                c.image = [UIImage systemImageNamed:@"plus.circle.fill"];
                c.textProperties.color = self.busy ? UIColor.secondaryLabelColor : UIColor.systemBlueColor;
                break;
            }
            if (indexPath.section == 0) {
                NSString *font = self.fonts[indexPath.row];
                c.text = font.lastPathComponent.stringByDeletingPathExtension;
                c.secondaryText = [NSByteCountFormatter stringFromByteCount:
                    (long long)[NSFileManager.defaultManager attributesOfItemAtPath:font error:nil].fileSize
                    countStyle:NSByteCountFormatterCountStyleFile];
                c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
                c.image = [UIImage systemImageNamed:@"textformat"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
            FontOWTarget t = (FontOWTarget)indexPath.row;
            bool replaced = fontow_is_replaced(t);
            c.text = fontow_target_title(t);
            c.secondaryText = !fontow_target_size(t) ? @"此 iOS 版本不支持"
                            : replaced ? @"已替换 — 点按还原原始字体" : @"Original";
            c.secondaryTextProperties.color = replaced ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
            if (!replaced) cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case LaraToolSpringBoard: {
            if (indexPath.section == 0 && indexPath.row == 2) {
                c.text = @"随插件一起应用";
                c.secondaryText = @"每次「应用插件」时也会套用这个外观，例如在重启 SpringBoard 之后。";
                c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
                UISwitch *sw = [UISwitch new];
                sw.on = [NSUserDefaults.standardUserDefaults boolForKey:kSettingsSBToolsWithTweaks];
                [sw addTarget:self action:@selector(sbWithTweaksChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                break;
            }
            if (indexPath.section == 0) {
                c.text = indexPath.row == 0 ? @"Apply" : @"全部重置";
                c.textProperties.color = self.busy ? UIColor.secondaryLabelColor
                                       : indexPath.row == 0 ? UIColor.systemBlueColor : UIColor.systemRedColor;
                break;
            }
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            const SBMatItem *item = [self sbItemForSection:indexPath.section];
            if (!item) break;
            if (indexPath.row == 0) {
                UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[ @"Visible", @"Color", @"Disabled" ]];
                seg.selectedSegmentIndex = MIN(MAX([[self sbChoiceFor:item][@"mode"] integerValue], 0), 2);
                seg.tag = indexPath.section;
                seg.enabled = !self.busy;
                [seg addTarget:self action:@selector(sbModeChanged:) forControlEvents:UIControlEventValueChanged];
                seg.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:seg];
                UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
                [NSLayoutConstraint activateConstraints:@[
                    [seg.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
                    [seg.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
                    [seg.topAnchor constraintEqualToAnchor:m.topAnchor],
                    [seg.bottomAnchor constraintEqualToAnchor:m.bottomAnchor],
                ]];
                cell.imageView.image = nil;
                return cell;
            }
            if (indexPath.row == 1) {
                c.text = @"Tint";
                UIColorWell *well = [UIColorWell new];
                well.supportsAlpha = YES;
                well.selectedColor = [self sbColorFor:item];
                well.tag = indexPath.section;
                [well addTarget:self action:@selector(sbColorChanged:) forControlEvents:UIControlEventValueChanged];
                [well sizeToFit];
                cell.accessoryView = well;
            } else {
                c.text = @"Blur";
                c.secondaryText = [NSString stringWithFormat:@"%.0f", [self sbBlurFor:item]];
                c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
                UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 180, 30)];
                slider.minimumValue = 0;
                slider.maximumValue = 60;
                slider.value = (float)[self sbBlurFor:item];
                slider.tag = indexPath.section;
                [slider addTarget:self action:@selector(sbBlurChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = slider;
            }
            break;
        }
        case LaraToolHiddenSettings: {
            const LaraPrefToggle *t = &lara_pref_toggles()[indexPath.row];
            c.text = [NSString stringWithUTF8String:t->title];
            c.secondaryText = [NSString stringWithUTF8String:t->detail];
            c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
            UISwitch *sw = [UISwitch new];
            NSNumber *state = self.prefStates[@(indexPath.row)];
            sw.on = state.boolValue;
            sw.enabled = !self.busy && state != nil;
            sw.tag = indexPath.row;
            [sw addTarget:self action:@selector(prefSwitched:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case LaraToolDecrypt: {
            if (indexPath.section == 0) {
                NSUInteger n = 0;
                for (NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:app_decrypt_output_dir() error:nil])
                    if ([f.pathExtension isEqualToString:@"ipa"]) n++;
                c.text = @"已解密的 IPA";
                c.secondaryText = n ? [NSString stringWithFormat:@"%lu 个 IPA%@ — 打开可分享或删除", (unsigned long)n, n == 1 ? @"" : @"s"]
                                    : @"还没有";
                c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
                c.image = [UIImage systemImageNamed:@"shippingbox.fill"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
            NSDictionary *app = self.jitApps[indexPath.row];
            c.text = app[@"name"];
            c.secondaryText = [NSString stringWithFormat:@"%@ · %@", app[@"bundleID"], app[@"version"]];
            c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
            c.image = app[@"icon"] ?: [UIImage systemImageNamed:@"app.dashed"];
            c.imageProperties.maximumSize = CGSizeMake(36, 36);
            c.imageProperties.cornerRadius = 8;
            break;
        }
        case LaraToolCards: {
            NSDictionary *card = self.jitApps[indexPath.row];
            c.text = card[@"name"];
            c.secondaryText = [card[@"hasBackup"] boolValue] ? @"自定义图片 — 点按更改或还原" : @"原始图片";
            c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
            c.image = card[@"preview"] ?: [UIImage systemImageNamed:@"creditcard"];
            c.imageProperties.maximumSize = CGSizeMake(64, 41);
            c.imageProperties.cornerRadius = 4;
            break;
        }
        case LaraToolAppLimit: {
            if (indexPath.section == 0) {
                NSUInteger marked = [self markedAppCount];
                c.text = marked ? [NSString stringWithFormat:@"移除限制标记（%lu）", (unsigned long)marked]
                                : @"没有应用计入限制";
                c.textProperties.color = (marked && !self.busy) ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
                break;
            }
            NSDictionary *app = self.jitApps[indexPath.row];
            int marked = [app[@"marked"] intValue];
            c.text = app[@"name"];
            c.secondaryText = marked == 1 ? @"计入限制" : marked == 0 ? @"不计入" : @"Unknown";
            c.secondaryTextProperties.color = marked == 1 ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
            c.image = app[@"icon"] ?: [UIImage systemImageNamed:@"app.dashed"];
            c.imageProperties.maximumSize = CGSizeMake(36, 36);
            c.imageProperties.cornerRadius = 8;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case LaraToolJIT: {
            NSDictionary *app = self.jitApps[indexPath.row];
            c.text = app[@"name"];
            c.secondaryText = app[@"bundleID"];
            c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
            c.image = app[@"icon"] ?: [UIImage systemImageNamed:@"app.dashed"];
            c.imageProperties.maximumSize = CGSizeMake(36, 36);
            c.imageProperties.cornerRadius = 8;
            break;
        }
    }
    cell.contentConfiguration = c;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.busy) return;
    __weak typeof(self) weakSelf = self;
    switch (self.tool) {
        case LaraToolPerformanceHUD: {
            int mode = kLaraHUDModes[indexPath.row].mode;
            [self runNamed:@"正在设置 HUD" work:^BOOL{ return lara_perf_hud_set_in_session(mode); }
                      done:^(BOOL ok) { if (ok) weakSelf.hudMode = mode; }];
            break;
        }
        case LaraToolDebugOverlay: {
            CGRect screen = self.view.window.windowScene.screen.bounds;   // UIKit: read here, on main
            [self runNamed:@"Enabling" work:^BOOL{ return lara_debug_overlay_enable_in_session(screen); }
                      done:^(BOOL ok) { if (ok) weakSelf.status = @"已启用。双击状态栏即可打开。"; }];
            break;
        }
        case LaraToolUpsideDown: {
            [self runNamed:@"Enabling" work:^BOOL{ return lara_upside_down_enable_in_session(); }
                      done:^(BOOL ok) { if (ok) weakSelf.status = @"已启用。把设备倒过来即可。"; }];
            break;
        }
        case LaraToolSpringBoard:
            if (indexPath.section != 0 || indexPath.row == 2) break;
            if (indexPath.row == 1) {
                [self.sbConfig removeAllObjects];
                [NSUserDefaults.standardUserDefaults removeObjectForKey:kSBMatConfigKey];
                [self.tableView reloadData];
            }
            [self sbApply];
            break;
        case LaraToolFonts:
            if (indexPath.section == 0) {
                if (indexPath.row == (NSInteger)self.fonts.count) [self fontsImport];
                else [self fontsChooseTargetFor:self.fonts[indexPath.row] at:indexPath];
            } else if (fontow_is_replaced((FontOWTarget)indexPath.row)) {
                [self fontsRun:NO target:(FontOWTarget)indexPath.row font:nil];
            }
            break;
        case LaraToolHiddenSettings:
            break;
        case LaraToolAppLimit:
            if (indexPath.section == 0 && [self markedAppCount] > 0) [self removeLimitMarks];
            break;
        case LaraToolCards:
            [self cardTapped:self.jitApps[indexPath.row] at:indexPath];
            break;
        case LaraToolDecrypt:
            if (indexPath.section == 0) {
                [self.navigationController pushViewController:[[FileBrowserViewController alloc] initWithPath:app_decrypt_output_dir()]
                                                     animated:YES];
            } else {
                [self confirmDecrypt:self.jitApps[indexPath.row]];
            }
            break;
        case LaraToolJIT: {
            NSDictionary *app = self.jitApps[indexPath.row];
            NSString *bid = app[@"bundleID"], *name = app[@"name"];
            __block int err = 0;
            [self runNamed:[NSString stringWithFormat:@"正在以 JIT 打开 %@", name]
                      work:^BOOL{ err = lara_jit_enable_in_session(bid); return err == 0; }
                      done:^(BOOL ok) {
                weakSelf.status = ok ? [NSString stringWithFormat:@"%@ 已开启 JIT，直到它退出。", name]
                    : err == ESRCH ? [NSString stringWithFormat:@"%@ 未能启动。请先打开一次，然后重试。", name]
                    : err == EPERM ? [NSString stringWithFormat:@"iOS 拒绝附加到 %@。它需要开发描述文件（get-task-allow）。", name]
                    : [NSString stringWithFormat:@"无法为 %@ 开启 JIT（错误 %d）。请查看日志。", name, err];
            }];
            break;
        }
    }
}

#pragma mark App decrypt

- (void)confirmDecrypt:(NSDictionary *)app
{
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"解密 %@？", app[@"name"]]
        message:@"为此应用生成一份解密的 IPA 供你自己使用（例如注入插件后侧载）。大型应用可能需要较长时间；请保持 Cyanide 打开。"
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Decrypt" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf decrypt:app];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)decrypt:(NSDictionary *)app
{
    if (self.busy) return;
    self.busy = YES;
    self.status = [NSString stringWithFormat:@"正在解密 %@…", app[@"name"]];
    // Show the progress where it's visible (the footer is below the list).
    self.navigationItem.prompt = self.status;
    [self showProgressBar];
    [self.tableView reloadData];
    // A large app takes a while: keep going for a bit if Cyanide is backgrounded.
    __block UIBackgroundTaskIdentifier bg = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"Decrypt" expirationHandler:^{
        [UIApplication.sharedApplication endBackgroundTask:bg];
        bg = UIBackgroundTaskInvalid;
    }];
    __weak typeof(self) weakSelf = self;
    __block NSString *ipa = nil, *error = nil;
    __block CFAbsoluteTime lastUI = 0;
    void (^progress)(NSString *, double) = ^(NSString *step, double fraction) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - lastUI < 0.25 && fraction < 1) return;   // don't flood the main queue
        lastUI = now;
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.status = [NSString stringWithFormat:@"%@ — %.0f %%", step, fraction * 100];
            weakSelf.navigationItem.prompt = [NSString stringWithFormat:@"%.0f %% · %@", fraction * 100, step];
            // Never backwards: retries restart a step at a lower fraction.
            UIProgressView *bar = weakSelf.progressBar;
            if (fraction > bar.progress) [bar setProgress:(float)fraction animated:YES];
        });
    };
    // Inside a SpringBoard session: when iOS won't decrypt in Cyanide,
    // SpringBoard does it (same kernel-access rules as the other tools).
    settings_springboard_tool_async("App Decrypt", ^BOOL{
        ipa = app_decrypt_make_ipa(app, YES, progress, &error);
        return ipa != nil;
    }, ^(BOOL ok, NSString *message) {
        if (bg != UIBackgroundTaskInvalid) { [UIApplication.sharedApplication endBackgroundTask:bg]; bg = UIBackgroundTaskInvalid; }
        typeof(self) me = weakSelf;
        if (!me) return;
        me.busy = NO;
        me.navigationItem.prompt = nil;
        [me.progressBar removeFromSuperview];
        me.progressBar = nil;
        if ([message isEqualToString:kSettingsFullExploitRequiredMessage]) {
            me.status = kSettingsNoKernelAccessHint;
            [me.tableView reloadData];
            settings_tool_needs_exploit(me, me.tableView, @"应用解密", ^{ [weakSelf decrypt:app]; });
            return;
        }
        NSString *failure = error ?: message ?: @"解密失败。请查看日志。";
        me.status = ipa ? [NSString stringWithFormat:@"已保存 %@。", ipa.lastPathComponent] : failure;
        [me.tableView reloadData];
        if (!me.view.window) return;
        // An alert, not just the footer: that is below the whole app list.
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:ipa ? @"IPA 已就绪" : @"解密失败"
                             message:ipa ? [NSString stringWithFormat:@"%@ 已保存到「已解密的 IPA」。%@", ipa.lastPathComponent,
                                            error.length ? [@"\n\n" stringByAppendingString:error] : @""] : failure
                      preferredStyle:UIAlertControllerStyleAlert];
        if (ipa) {
            NSString *path = ipa;
            [ac addAction:[UIAlertAction actionWithTitle:@"分享…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                typeof(self) me2 = weakSelf;
                UITableViewCell *cell = [me2.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                if (me2) filebrowser_share_file(me2, path, NO, nil, cell, nil);
            }]];
        }
        [ac addAction:[UIAlertAction actionWithTitle:ipa ? @"Done" : @"OK" style:UIAlertActionStyleCancel handler:nil]];
        [me presentViewController:ac animated:YES completion:nil];
    });
}

- (void)showProgressBar
{
    [self.progressBar removeFromSuperview];
    UINavigationBar *navBar = self.navigationController.navigationBar;
    if (!navBar) return;
    UIProgressView *bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [navBar addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:navBar.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:navBar.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:navBar.bottomAnchor],
    ]];
    self.progressBar = bar;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    // The bar lives on the shared navigation bar: don't leave it on other screens.
    self.progressBar.hidden = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.progressBar.hidden = NO;
}

#pragma mark Wallet card art

- (void)cardTapped:(NSDictionary *)card at:(NSIndexPath *)indexPath
{
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:card[@"name"] message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"选择图片…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf pickImageForCard:card];
    }]];
    if ([card[@"hasBackup"] boolValue]) {
        [ac addAction:[UIAlertAction actionWithTitle:@"还原原始图片" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            NSString *err = nil;
            BOOL ok = lara_wallet_card_restore(card, &err);
            weakSelf.status = ok ? @"已还原原始图片。重启 SpringBoard 或重新打开钱包即可看到。" : err;
            [weakSelf listJITApps];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    ac.popoverPresentationController.sourceView = cell ?: self.view;
    ac.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)pickImageForCard:(NSDictionary *)card
{
    self.pickingCard = card;
    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
    cfg.filter = PHPickerFilter.imagesFilter;
    cfg.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSDictionary *card = self.pickingCard;
    self.pickingCard = nil;
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (!card || ![provider canLoadObjectOfClass:UIImage.class]) return;
    __weak typeof(self) weakSelf = self;
    [provider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([object isKindOfClass:UIImage.class]) [weakSelf applyImage:(UIImage *)object toCard:card];
        });
    }];
}

// Scales the picture to fill the original card image (same pixel size, so
// Wallet lays it out exactly like the original), then writes it.
- (void)applyImage:(UIImage *)picked toCard:(NSDictionary *)card
{
    UIImage *original = [UIImage imageWithContentsOfFile:card[@"imagePath"]];
    CGSize px = original ? CGSizeMake(original.size.width * original.scale, original.size.height * original.scale)
                         : CGSizeMake(1536, 969);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = 1;
    fmt.opaque = YES;
    UIImage *scaled = [[[UIGraphicsImageRenderer alloc] initWithSize:px format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat k = MAX(px.width / picked.size.width, px.height / picked.size.height);
        CGSize s = CGSizeMake(picked.size.width * k, picked.size.height * k);
        [picked drawInRect:CGRectMake((px.width - s.width) / 2, (px.height - s.height) / 2, s.width, s.height)];
    }];
    NSString *err = nil;
    BOOL ok = lara_wallet_card_set_image(card, UIImagePNGRepresentation(scaled), &err);
    self.status = ok ? @"卡片图案已替换。重启 SpringBoard 或重新打开钱包即可看到。" : err;
    [self listJITApps];
}

// Removes installd's free-profile mark from every counted app, as root
// through launchd (the bundles stay owned by installd), then rescans.
- (void)removeLimitMarks
{
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSDictionary *app in self.jitApps) if ([app[@"marked"] intValue] == 1) [paths addObject:app[@"path"]];
    if (!paths.count || self.busy) return;
    self.busy = YES;
    self.status = @"正在移除标记…";
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSUInteger done = 0;
        NSString *lastError = nil;
        for (NSString *path in paths) {
            NSString *err = nil;
            if (settings_root_remove_xattr(path, kLaraFreeProfileXattr, &err)) done++;
            else lastError = err;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) me = weakSelf;
            if (!me) return;
            me.busy = NO;
            [me listJITApps];
            me.status = done == paths.count
                ? [NSString stringWithFormat:@"已从 %lu 个应用%@移除标记。", (unsigned long)done, done == 1 ? @"" : @"s"]
                : [NSString stringWithFormat:@"已移除 %lu / %lu：%@", (unsigned long)done, (unsigned long)paths.count,
                                             lastError ?: @"查看日志"];
        });
    });
}

- (void)prefSwitched:(UISwitch *)sw
{
    NSInteger index = sw.tag;
    BOOL on = sw.isOn;
    const LaraPrefToggle *t = &lara_pref_toggles()[index];
    __weak typeof(self) weakSelf = self;
    [self runNamed:@"Saving" work:^BOOL{ return lara_pref_set_in_session(t, on); }
              done:^(BOOL ok) {
        typeof(self) me = weakSelf;
        if (ok) {
            me.prefStates[@(index)] = @(on);
            me.status = @"已保存。重启 SpringBoard 后生效。";
        }
    }];
}

@end
