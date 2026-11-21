import Flutter
import UIKit
import Symbols
import SwiftUI

class SceneDelegate: FlutterSceneDelegate {
  @available(iOS 26.0, *)
  override func preferredWindowingControlStyle(
    for windowScene: UIWindowScene
  ) -> UIWindowScene.WindowingControlStyle {
    return .minimal
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // FlutterSceneDelegate declares this method but may not implement it.
    if FlutterSceneDelegate.instancesRespond(
      to: #selector(UISceneDelegate.scene(_:willConnectTo:options:)))
    {
      super.scene(scene, willConnectTo: session, options: connectionOptions)
    }
    // iPhone on iOS 26+: host Flutter in a native tab bar controller so the
    // main navigation uses the system Liquid Glass tab bar, which iPhone Duo
    // also places in its vertical status bar.
    if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .phone,
      let window,
      let flutterViewController = window.rootViewController as? FlutterViewController
    {
      let tabs = NativeTabBarController(flutterViewController: flutterViewController)
      let navigation = NativePageNavigationController(rootViewController: tabs)
      navigation.onInteractionBlockChanged = { [weak tabs] blocked in
        tabs?.setInteractionBlocked(blocked)
      }
      navigation.onHome = { [weak tabs] completion in tabs?.requestHome(completion: completion) }
      navigation.onBack = { [weak tabs] completion in
        tabs?.requestBack(completion: completion)
      }
      navigation.onPageAction = { [weak tabs] owner, id, completion in
        tabs?.requestPageAction(owner: owner, id: id, completion: completion)
      }
      navigation.onCommentAction = { [weak tabs] owner, completion in
        tabs?.requestCommentAction(owner: owner, completion: completion)
      }
      navigation.onCommentVisibilityChange = { [weak tabs] owner, visible in
        tabs?.publishCommentVisibility(owner: owner, visible: visible)
      }
      navigation.onVisibilityChange = { [weak tabs] back, actions, video, home in
        tabs?.publishBarVisibility(back: back, actions: actions, video: video, home: home)
      }
      window.rootViewController = navigation
    }
  }
}

/// Hosts the single Flutter view inside whichever tab is selected. Dart sends
/// the tabs over `piliplus/native_tab_bar`; until then the tab bar is hidden
/// and Flutter draws its own navigation.
@available(iOS 26.0, *)
final class NativeTabBarController: UITabBarController, UITabBarControllerDelegate {
  private let flutterViewController: FlutterViewController
  private var channel: FlutterMethodChannel?

  init(flutterViewController: FlutterViewController) {
    self.flutterViewController = flutterViewController
    super.init(nibName: nil, bundle: nil)
    delegate = self
    let channel = FlutterMethodChannel(
      name: "piliplus/native_tab_bar",
      binaryMessenger: flutterViewController.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
    let host = makeHost()
    viewControllers = [host]
    host.embed(flutterViewController)
    setTabBarHidden(true, animated: false)
  }

  private var safeArea = UIEdgeInsets.zero
  private var canGoBack = false
  private var isPlayerFullScreen = false
  private var tabsConfigured = false
  private var requestedTabBarHidden = true
  private var appliedTabBarHidden = true
  private var videoChrome: [String: Any]?
  private var interactionBlocked = false
  func setInteractionBlocked(_ blocked: Bool) {
    interactionBlocked = blocked
    updateTabBarVisibility(animated: false)
  }
  var isInnerDisplay: Bool {
    guard let screen = view.window?.windowScene?.screen else { return false }
    return min(screen.bounds.width, screen.bounds.height) >= 600
  }
  private var navigationHost: NativePageNavigationController? {
    navigationController as? NativePageNavigationController
  }

  private func updateBackButton() {
    navigationHost?.setPageState(canGoBack: canGoBack, fullScreen: isPlayerFullScreen)
  }

  private var railTransition: DuoRailTransition?
  private var lastRailTransitionID = 0
  private weak var flutterSurface: DuoFlutterSurfaceView?

  func setFlutterSurface(_ surface: DuoFlutterSurfaceView?) {
    let opaque = !hasVerticalBar
    if flutterViewController.isViewOpaque != opaque { flutterViewController.isViewOpaque = opaque }
    // Changing the controller flag after its view loads does not reliably
    // clear FlutterView/CAMetalLayer opacity. Keep all three in agreement.
    if flutterViewController.view.isOpaque != opaque { flutterViewController.view.isOpaque = opaque }
    if flutterViewController.view.layer.isOpaque != opaque { flutterViewController.view.layer.isOpaque = opaque }
    guard flutterSurface !== surface else { return }
    flutterSurface = surface
    flutterViewController.view.backgroundColor = opaque ? .systemBackground : .clear
    for host in viewControllers?.compactMap({ $0 as? FlutterHostViewController }) ?? [] {
      host.setFlutterSurface(surface)
    }
    updateTabBarVisibility(animated: false)
    channel?.invokeMethod("pageSurfaceRaised", arguments: surface != nil)
  }

  private func updateTabBarVisibility(animated: Bool) {
    let fullScreen = isPlayerFullScreen || (videoChrome?["fullScreen"] as? Bool ?? false)
    // On Duo the actual page surface lives above UITabBar. Secondary pages
    // cover the still-mounted system tabs with their own opaque background.
    let hidden = !tabsConfigured || fullScreen
      || (!hasVerticalBar && (canGoBack || requestedTabBarHidden || interactionBlocked))
    if hidden != appliedTabBarHidden || isTabBarHidden != hidden {
      appliedTabBarHidden = hidden
      setTabBarHidden(hidden, animated: hasVerticalBar ? false : animated)
    }
    let interactive = !canGoBack && !interactionBlocked && railTransition == nil && !fullScreen
    flutterSurface?.railWidth = hasVerticalBar ? max(72, max(safeArea.right, view.safeAreaInsets.right)) : 0
    flutterSurface?.passesRootRailTouches = hasVerticalBar && interactive
  }

  func requestHome(completion: @escaping () -> Void) {
    channel?.invokeMethod("home", arguments: nil) { _ in completion() }
  }

  func requestBack(completion: @escaping () -> Void) {
    channel?.invokeMethod("back", arguments: nil) { _ in completion() }
  }

  func requestPageAction(owner: Int, id: String, completion: @escaping () -> Void) {
    channel?.invokeMethod("pageAction", arguments: ["owner": owner, "id": id]) {
      _ in completion()
    }
  }

  func requestCommentAction(owner: Int, completion: @escaping () -> Void) {
    channel?.invokeMethod("commentAction", arguments: owner) { _ in completion() }
  }

  func publishCommentVisibility(owner: Int, visible: Bool) {
    channel?.invokeMethod("commentButtonVisible", arguments: ["owner": owner, "visible": visible])
  }

  func publishBarVisibility(back: Bool, actions: Bool, video: Bool, home: Bool) {
    channel?.invokeMethod("homeToolsVisible", arguments: home)
    channel?.invokeMethod("backButtonVisible", arguments: back)
    channel?.invokeMethod("pageActionsVisible", arguments: actions)
    channel?.invokeMethod("videoNavigationEnabled", arguments: video)
  }

  private func makeHost() -> FlutterHostViewController {
    let host = FlutterHostViewController()
    host.setFlutterSurface(flutterSurface)
    host.onSafeAreaChange = { [weak self, weak host] insets in
      guard let self, let host else { return }
      self.safeAreaHost = host
      self.publishSafeArea(insets, of: host)
    }
    host.onLayout = { [weak self, weak host] in
      guard let self, let view = host?.view else { return }
      self.updateTopBarRegion(view)
    }
    return host
  }

  /// The host that last reported its safe area, to send it again after the
  /// home page shows the status bar (see [mainHidesStatusBar]).
  private weak var safeAreaHost: FlutterHostViewController?

  private func publishSafeArea(_ insets: UIEdgeInsets, of host: FlutterHostViewController) {
    // A host outside the window (a tab that is not shown yet, when embed()
    // moves Flutter into it) reports all zeros, and Dart would lay out one
    // frame without the safe area. The real insets follow once the host is
    // in the window (viewIsAppearing / viewSafeAreaInsetsDidChange).
    guard let window = host.view.window else { return }
    var insets = insets
    // iPhone Duo: UIKit moves the navigation bar into the vertical bar but
    // still adds its height to the top safe area. Nothing is drawn there, so
    // keep the window's own top inset and the page does not move down.
    insets.top = min(insets.top, window.safeAreaInsets.top)
    // iPhone Duo: while the status bar sits in the vertical bar on the side,
    // nothing is shown at the top edge, but a real device can still report a
    // top inset (about 20pt; the simulator reports 0), which left an empty
    // strip above every page. Normal iPhones in landscape have at most about
    // 62pt on the Dynamic Island side, so 72 only matches the vertical bar.
    if max(insets.left, insets.right) >= 72 {
      insets.top = 0
    }
    // iPhone Duo unfolded in portrait: the home page hides the status bar
    // while its top bar is scrolled away, and draws its own row where the
    // status bar was. The top inset dropping to 0 in the middle of the drag
    // would make Flutter lay out the whole app again and the bar stutter,
    // so keep the inset from before; it is sent again once the status bar
    // is shown (see mainHidesStatusBar).
    if mainHidesStatusBar {
      insets.top = safeArea.top
    }
    guard insets != self.safeArea else { return }
    self.safeArea = insets
    self.updateBackButton()
    self.channel?.invokeMethod("safeArea", arguments: Self.encode(insets))
  }

  // iPhone Duo unfolded in portrait: the status bar sits only in the top-right
  // corner, and the system reserves just that corner. The home page puts its
  // own row of buttons in the rest of the status bar row, at the place UIKit
  // gives for a top bar, so nothing is hard-coded to a particular device.
  private static let topBarExtent: CGFloat = 44
  private var topBarRegion: [String: Double]?

  private func updateTopBarRegion(_ view: UIView) {
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        guard let window = view.window else { return }
        // Pages hide the status bar (the video page, the home page while its
        // top bar is scrolled away); then the corner is not reserved. Keep the
        // values from when it was shown so the layout does not jump.
        if window.windowScene?.statusBarManager?.isStatusBarHidden ?? false { return }
        var region: [String: Double]?
        let width = view.bounds.width
        let topCorner = view.reservedRegions(kind: .occlusion).contains {
          $0.frame.minY <= 0 && $0.frame.height > 0 && $0.frame.width < width / 2
        }
        if traitCollection.verticalBarEdge == .unspecified && topCorner {
          let bar = view.edgeInsets(for: .bar(onEdge: UIRectEdge.top, extent: Self.topBarExtent))
          // UIKit centers a top bar in the status bar row but keeps it at
          // least some distance from the top edge; a tall bar shows that
          // distance. Dart places bars of other heights (an app bar is 56)
          // the same way.
          let tall = view.edgeInsets(for: .bar(onEdge: UIRectEdge.top, extent: 64))
          region = [
            "height": min(view.safeAreaInsets.top, window.safeAreaInsets.top),
            "top": bar.top, "left": bar.left, "right": bar.right,
            "extent": Self.topBarExtent,
            "center": bar.top + Self.topBarExtent / 2,
            "minTop": tall.top,
          ]
        }
        guard region != topBarRegion else { return }
        topBarRegion = region
        channel?.invokeMethod("topBarRegion", arguments: region)
      }
    #endif
  }

  private static func encode(_ insets: UIEdgeInsets) -> [String: Double] {
    [
      "top": insets.top, "left": insets.left,
      "bottom": insets.bottom, "right": insets.right,
    ]
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func applyNavigationState(_ state: [String: Any]) {
    if let page = state["page"] as? [String: Any] {
      videoChrome = page["video"] as? [String: Any]
      if videoChrome == nil && isPlayerFullScreen { isPlayerFullScreen = false; updateBackButton() }
      canGoBack = page["canGoBack"] as? Bool ?? canGoBack
      navigationHost?.setPageActions(owner: page["owner"] as? Int ?? 0,
        items: page["items"] as? [[String: Any]] ?? [], video: videoChrome,
        homeTools: page["homeTools"] as? Bool ?? false, canGoBack: canGoBack, backOnly: page["backOnly"] as? Bool ?? true)
    }
    if let presentation = state["presentation"] as? [String: Any] {
      navigationHost?.setModalOverlayVisible(presentation["modal"] as? Bool ?? false)
    }
    if let comment = state["comment"] as? [String: Any] {
      navigationHost?.setCommentAction(owner: comment["owner"] as? Int ?? 0,
        visible: comment["visible"] as? Bool ?? false,
        label: comment["label"] as? String ?? "发表评论")
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setSurfaceAppearance":
      if let args = call.arguments as? [String: Any], let argb = args["color"] as? Int {
        let color = UIColor(red: CGFloat((argb >> 16) & 255) / 255,
          green: CGFloat((argb >> 8) & 255) / 255, blue: CGFloat(argb & 255) / 255,
          alpha: CGFloat((argb >> 24) & 255) / 255)
        let style: UIUserInterfaceStyle = (args["dark"] as? Bool ?? false) ? .dark : .light
        overrideUserInterfaceStyle = style
        view.backgroundColor = color
        navigationHost?.overrideUserInterfaceStyle = style
        navigationHost?.view.backgroundColor = color
      }
      result(nil)
    case "setRailTransition":
      if let state = DuoRailTransition(call.arguments) {
        if state.id >= lastRailTransitionID {
          lastRailTransitionID = state.id
          railTransition = state.active ? state : nil
          navigationHost?.performNavigationUpdates {
            if let arguments = call.arguments as? [String: Any],
              let initial = arguments["navigation"] as? [String: Any] {
              applyNavigationState(initial)
            }
            navigationHost?.setRailTransition(state)
          }
          updateTabBarVisibility(animated: false)
          if let arguments = call.arguments as? [String: Any], arguments["navigation"] != nil {
            verticalBarDidChange()
          }
        }
      }
      result(nil)
    case "setNavigationState":
      let state = call.arguments as? [String: Any] ?? [:]
      navigationHost?.performNavigationUpdates { applyNavigationState(state) }
      verticalBarDidChange()
      result(nil)
    case "setCommentAction":
      let args = call.arguments as? [String: Any] ?? [:]
      navigationHost?.setCommentAction(owner: args["owner"] as? Int ?? 0,
        visible: args["visible"] as? Bool ?? false, label: args["label"] as? String ?? "发表评论")
      result(nil)
    case "setPageActions":
      if let args = call.arguments as? [String: Any] {
        videoChrome = args["video"] as? [String: Any]
        canGoBack = args["canGoBack"] as? Bool ?? canGoBack
        navigationHost?.setPageActions(
          owner: args["owner"] as? Int ?? 0,
          items: args["items"] as? [[String: Any]] ?? [], video: videoChrome,
          homeTools: args["homeTools"] as? Bool ?? false, canGoBack: canGoBack, backOnly: args["backOnly"] as? Bool ?? true)
        verticalBarDidChange()
      }
      result(nil)
    case "setCanGoBack":
      canGoBack = call.arguments as? Bool ?? false
      updateBackButton()
      updateTabBarVisibility(animated: true)
      result(nil)
    case "setFullScreen":
      isPlayerFullScreen = call.arguments as? Bool ?? false
      updateBackButton()
      verticalBarDidChange(forceStatusUpdate: true)
      result(nil)
    case "getNavigationCapabilities":
      result(["verticalRail": hasVerticalBar, "commentActions": true])
    case "getSafeArea":
      result(Self.encode(safeArea))
    case "getTopBarRegion":
      result(topBarRegion)
    case "setMainHidesStatusBar":
      mainHidesStatusBar = call.arguments as? Bool ?? false
      result(nil)
    case "setTabs":
      guard let args = call.arguments as? [String: Any],
        let tabs = args["tabs"] as? [[String: String]], tabs.count > 1
      else { return result(false) }
      let selected = min(args["selected"] as? Int ?? 0, tabs.count - 1)
      let hosts = tabs.map { tab -> FlutterHostViewController in
        let host = makeHost()
        let symbols = Self.symbols(for: tab["id"] ?? "")
        host.tabBarItem = UITabBarItem(
          title: tab["title"],
          image: UIImage(systemName: symbols.normal),
          selectedImage: UIImage(systemName: symbols.selected))
        return host
      }
      hosts[selected].embed(flutterViewController)
      viewControllers = hosts
      selectedIndex = selected
      tabsConfigured = true
      requestedTabBarHidden = false
      updateTabBarVisibility(animated: false)
      result(true)
    case "setSelected":
      if let index = call.arguments as? Int { select(index) }
      result(nil)
    case "setBadge":
      if let args = call.arguments as? [String: Any], let index = args["index"] as? Int,
        let item = viewControllers?[safe: index]?.tabBarItem
      {
        item.badgeValue = args["value"] as? String

      }
      result(nil)
    case "setHidden":
      requestedTabBarHidden = call.arguments as? Bool ?? false
      updateTabBarVisibility(animated: true)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func symbols(for id: String) -> (normal: String, selected: String) {
    switch id {
    case "home": return ("house", "house.fill")
    case "dynamics": return ("circle.dashed", "circle.dashed.inset.filled")
    case "mine": return ("person", "person.fill")
    default: return ("circle", "circle.fill")
    }
  }

  private func select(_ index: Int) {
    guard let host = viewControllers?[safe: index] as? FlutterHostViewController,
      index != selectedIndex
    else { return }
    host.embed(flutterViewController)
    selectedIndex = index
  }

  func tabBarController(
    _ tabBarController: UITabBarController, shouldSelect viewController: UIViewController
  ) -> Bool {
    guard !canGoBack, !interactionBlocked, railTransition == nil else { return false }
    // Move the Flutter view into the tab before UIKit shows it.
    (viewController as? FlutterHostViewController)?.embed(flutterViewController)
    return true
  }

  func tabBarController(
    _ tabBarController: UITabBarController, didSelect viewController: UIViewController
  ) {
    channel?.invokeMethod("select", arguments: selectedIndex)
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    flutterViewController.supportedInterfaceOrientations
  }

  // Normal Duo pages retain the system rail. Only fullscreen hides it; video
  // pixels can extend underneath without changing the rest of the page's inset.
  private var hasVerticalBar = false {
    didSet { verticalBarDidChange() }
  }
  private var isVerticalBarHidden: Bool {
    guard hasVerticalBar else { return false }
    return DuoStatusBarPolicy.hidesStatusIcons(
      inner: isInnerDisplay, playerFullScreen: isPlayerFullScreen, video: videoChrome)
  }
  private var sentVerticalBarHidden = false

  private func verticalBarDidChange(forceStatusUpdate: Bool = false) {
    updateTabBarVisibility(animated: true)
    let hidden = isVerticalBarHidden
    guard hidden != sentVerticalBarHidden else {
      if forceStatusUpdate { setNeedsStatusBarAppearanceUpdate() }
      return
    }
    sentVerticalBarHidden = hidden
    UIView.animate(withDuration: 0.25) { self.setNeedsStatusBarAppearanceUpdate() }
    channel?.invokeMethod("verticalBarHidden", arguments: hidden)
  }

  private var mainHidesStatusBar = false {
    didSet {
      guard mainHidesStatusBar != oldValue else { return }
      statusBarDidChange()
      // The top inset was held while the status bar was hidden. Once it is
      // shown and laid out again, send the real insets, in case they changed
      // in the meantime (a rotation) without another safe area change.
      if !mainHidesStatusBar {
        DispatchQueue.main.async { [weak self] in
          guard let self, let host = self.safeAreaHost else { return }
          self.publishSafeArea(host.view.safeAreaInsets, of: host)
        }
      }
    }
  }

  private func statusBarDidChange() {
    UIView.animate(withDuration: 0.25) { self.setNeedsStatusBarAppearanceUpdate() }
  }

  override var childForStatusBarHidden: UIViewController? {
    hasVerticalBar || mainHidesStatusBar ? nil : super.childForStatusBarHidden
  }

  override var prefersStatusBarHidden: Bool {
    hasVerticalBar ? isVerticalBarHidden : (mainHidesStatusBar || super.prefersStatusBarHidden)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateBackButton()
    // The vertical bar edge stays set while the status bar is hidden, and
    // changes when the device folds or unfolds.
    var hasVerticalBar = false
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        hasVerticalBar = traitCollection.verticalBarEdge != .unspecified
      }
    #endif
    if hasVerticalBar != self.hasVerticalBar {
      self.hasVerticalBar = hasVerticalBar
      channel?.invokeMethod("rightRailDevice", arguments: hasVerticalBar)
    }
    verticalBarDidChange()
  }

  // The tabs do not forward appearance callbacks, so deliver this controller's
  // appearance to Flutter directly. FlutterViewController creates its rendering
  // surface in viewWillAppear only once the viewport size is known, and
  // otherwise only on first layout or scene activation while active; on device
  // both can be missed at launch, leaving the launch screen up. The first
  // appearance is therefore delivered after this view is in the window and laid
  // out.
  private var hasFlutterAppeared = false

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    if hasFlutterAppeared {
      flutterViewController.beginAppearanceTransition(true, animated: animated)
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updateBackButton()
    verticalBarDidChange(forceStatusUpdate: true)
    if hasFlutterAppeared {
      flutterViewController.endAppearanceTransition()
    } else {
      hasFlutterAppeared = true
      flutterViewController.view.layoutIfNeeded()
      flutterViewController.beginAppearanceTransition(true, animated: false)
      flutterViewController.endAppearanceTransition()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    flutterViewController.beginAppearanceTransition(false, animated: animated)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    flutterViewController.endAppearanceTransition()
  }
}

/// A tab's content controller; it only holds the shared Flutter view controller
/// and forwards system appearance queries to it. Appearance callbacks are not
/// forwarded, so moving Flutter between tabs does not pause the engine.
final class FlutterHostViewController: UIViewController {
  override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
  override var childForStatusBarStyle: UIViewController? { children.first }
  override var childForStatusBarHidden: UIViewController? { children.first }
  override var childForHomeIndicatorAutoHidden: UIViewController? { children.first }
  override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
    children.first
  }
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    children.first?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
  }

  private weak var flutterSurface: UIView?
  func setFlutterSurface(_ surface: UIView?) {
    guard flutterSurface !== surface else { return }
    flutterSurface = surface
    if let child = children.first { placeFlutterView(child) }
  }

  private func placeFlutterView(_ child: UIViewController) {
    let target = flutterSurface ?? view!
    guard child.view.superview !== target else { return }
    child.view.removeFromSuperview()
    child.view.translatesAutoresizingMaskIntoConstraints = false
    target.addSubview(child.view)
    NSLayoutConstraint.activate([
      child.view.leadingAnchor.constraint(equalTo: target.leadingAnchor),
      child.view.trailingAnchor.constraint(equalTo: target.trailingAnchor),
      child.view.topAnchor.constraint(equalTo: target.topAnchor),
      child.view.bottomAnchor.constraint(equalTo: target.bottomAnchor),
    ])
  }

  func embed(_ child: UIViewController) {
    if child.parent === self { placeFlutterView(child); return }
    child.willMove(toParent: nil)
    child.view.removeFromSuperview()
    child.removeFromParent()
    addChild(child)
    placeFlutterView(child)
    child.didMove(toParent: self)
    onSafeAreaChange?(view.safeAreaInsets)
  }

  /// The Flutter view reports no safe area when it is not the window's root
  /// controller, so the tab bar controller forwards this one to Dart.
  var onSafeAreaChange: ((UIEdgeInsets) -> Void)?

  /// Reserved regions are only known after layout.
  var onLayout: (() -> Void)?

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if !children.isEmpty { onLayout?() }
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    if !children.isEmpty { onSafeAreaChange?(view.safeAreaInsets) }
  }

  /// In the window with up-to-date insets, before the tab is first drawn.
  /// embed() skips its report while the host is outside the window, and the
  /// insets need not change on the way in, so report them here as well; the
  /// tab bar controller drops values it has already sent.
  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    if !children.isEmpty { onSafeAreaChange?(view.safeAreaInsets) }
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

/// Flutter paints the real page transition here, above the real UITabBar.
/// The root page leaves its rail transparent; detail pages paint it normally.
final class DuoFlutterSurfaceView: UIView {
  var railWidth: CGFloat = 0
  var passesRootRailTouches = false
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    if passesRootRailTouches && point.x >= bounds.width - railWidth { return false }
    return super.point(inside: point, with: event)
  }
}

/// Normalized Flutter route progress; UIKit never estimates gesture duration.
struct DuoRailTransition {
  let id: Int
  let secondary: CGFloat
  let active: Bool
  let returning: Bool
  let interactive: Bool
  let committed: Bool?
  let destinationSecondary: CGFloat?
  init?(_ arguments: Any?) {
    guard let map = arguments as? [String: Any], let id = map["id"] as? Int,
      let value = map["secondary"] as? Double, value.isFinite,
      let active = map["active"] as? Bool, let returning = map["returning"] as? Bool else { return nil }
    self.id = id
    secondary = min(1, max(0, CGFloat(value)))
    self.active = active
    self.returning = returning
    interactive = map["interactive"] as? Bool ?? false
    committed = (map["committed"] as? Bool) ?? (returning && !interactive ? true : nil)
    destinationSecondary = (map["destinationSecondary"] as? Double).map { min(1, max(0, CGFloat($0))) }
  }
}

struct DuoRailMotion {
  static func smooth(_ value: CGFloat) -> CGFloat {
    let x = min(1, max(0, value))
    return x * x * (3 - 2 * x)
  }
  // Interactive motion uses the route's position; released motion uses UIKit.
  static func dock(_ secondary: CGFloat) -> CGFloat { smooth(secondary / 0.55) }
}

// MARK: - Fold orientation policy

/// Fullscreen takes precedence over the inner display's normal persistent icons.
/// Either fullscreen signal is sufficient while Dart/native updates settle.
struct DuoStatusBarPolicy {
  static func hidesStatusIcons(inner: Bool, playerFullScreen: Bool, video: [String: Any]?) -> Bool {
    if playerFullScreen || (video?["fullScreen"] as? Bool ?? false) { return true }
    if inner { return false }
    guard let video else { return false }
    return !(video["collapsed"] as? Bool ?? false)
      && !(video["paused"] as? Bool ?? false)
  }
}

// UIKit picks the inner display's orientation from the lock in effect before
// the device unfolds, so a portrait-only lock leaves the interface in the inner
// display's native orientation, rotated relative to the device. Release the
// lock as soon as the hinge leaves the closed state, before the scene moves to
// the inner display. Dart restores it after the device closes again.
class DuoFlutterViewController: FlutterViewController {
  private var isHingeOpen = false

  override func viewDidLoad() {
    super.viewDidLoad()
    // UIHinge ships in the iOS 27.1 SDK (Xcode 27, Swift 6.4); older Xcode
    // versions build without hinge handling.
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        let interaction = UIHingeInteraction { [weak self] _, update in
          self?.hingeDidUpdate(update.hinge)
        }
        view.addInteraction(interaction)
      }
    #endif
  }

  #if compiler(>=6.4)
    @available(iOS 27.1, *)
    private func hingeDidUpdate(_ hinge: UIHinge?) {
      let isOpen = hinge.map { $0.status != .closed && $0.status != .unknown } ?? false
      guard isOpen != isHingeOpen else { return }
      isHingeOpen = isOpen
      setNeedsUpdateOfSupportedInterfaceOrientations()
      // Flutter also stores the lock as the scene's geometry preference, which
      // UIKit uses when the scene moves to the inner display. Clear it while the
      // scene is still on the outer display, where programmatic changes are
      // allowed.
      if isOpen, let windowScene = view.window?.windowScene {
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
      }
    }
  #endif

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    isHingeOpen ? .all : super.supportedInterfaceOrientations
  }

  // When hosted in NativeTabBarController, UIKit reads orientations from the
  // root controller, so forward Flutter's update requests to it.
  @available(iOS 16.0, *)
  override func setNeedsUpdateOfSupportedInterfaceOrientations() {
    super.setNeedsUpdateOfSupportedInterfaceOrientations()
    if let root = view.window?.rootViewController, root !== self {
      root.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
  }
}


// MARK: - System-managed page navigation and actions

/// UIKit owns the bar geometry, including the space below Duo's status icons.
/// Flutter keeps its own route stack and receives all button actions.
/// A transparent, noninteractive navigation item supplies UIKit's real leading
/// control position. UIKit moves it below status icons and expanded Live Activities.
@available(iOS 26.0, *)
private final class DuoNavigationAnchorView: UIView {
  var geometryChanged: (() -> Void)?
  private var lastFrame: CGRect?
  override func layoutSubviews() {
    super.layoutSubviews()
    guard let window else { return }
    let frame = convert(bounds, to: window)
    if lastFrame != frame {
      lastFrame = frame
      geometryChanged?()
    }
  }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    lastFrame = nil
    setNeedsLayout()
  }
}

@available(iOS 26.0, *)
private final class DuoRailDisplayLinkTarget: NSObject {
  var tick: (() -> Void)?
  @objc func refresh() { tick?() }
}

// These controls use Apple's glass renderer and interaction directly. No
// isHighlighted overrides, pressed backgrounds, transforms or custom ButtonStyle.
@available(iOS 26.0, *)
private struct DuoGlassAction: Identifiable, Equatable {
  var id: String
  var symbol: String
  var title: String
  var count: String? = nil
  var enabled = true
  var selected = false
  var color: UIColor = .label
  var badge: String? = nil
  var height: CGFloat { count == nil ? 44 : 48 }
}

@available(iOS 26.0, *)
private struct DuoGlassState: Equatable {
  var commands: [DuoGlassAction] = []
  var fullscreen: DuoGlassAction? = nil
  var visible = false
  var enabled = true
  var standalone = false
}

@available(iOS 26.0, *)
private final class DuoGlassModel: ObservableObject {
  @Published private(set) var state = DuoGlassState()
  var onAction: ((String) -> Void)?
  func update(_ value: DuoGlassState, animated: Bool, completion: (() -> Void)? = nil) {
    guard value != state else { completion?(); return }
    if animated && !UIAccessibility.isReduceMotionEnabled {
      // Use the system's default animation and glass transitions. The renderer
      // handles materialization and geometry; the app never scales the surface.
      withAnimation(completionCriteria: .removed) { state = value } completion: { completion?() }
    } else {
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) { state = value }
      completion?()
    }
  }
}

@available(iOS 26.0, *)
private struct DuoGlassControls: View {
  @ObservedObject var model: DuoGlassModel
  @Namespace private var glassNamespace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private func control(_ action: DuoGlassAction, union: String, glassID: String) -> some View {
    Button { model.onAction?(action.id) } label: {
      VStack(spacing: action.count == nil ? 0 : 3) {
        Image(systemName: action.symbol)
          .font(.system(size: 18.5))
          .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        if let count = action.count {
          Text(count).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
        }
      }
      .foregroundStyle(Color(uiColor: action.color))
      .frame(width: 44, height: action.height)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .topTrailing) {
      if let badge = action.badge {
        Text(badge.isEmpty ? "•" : badge)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.white).padding(.horizontal, 4)
          .background(.red, in: Capsule()).allowsHitTesting(false)
      }
    }
    // Apple documents interactive() as providing the same fluid reaction as
    // the built-in glass ButtonStyle, including on custom-sized controls.
    .glassEffect(.regular.interactive(), in: .capsule)
    .glassEffectUnion(id: union, namespace: glassNamespace)
    .glassEffectID(glassID, in: glassNamespace)
    .glassEffectTransition(reduceMotion || model.state.standalone || union == "fullscreen" ? .materialize : .matchedGeometry)
    .disabled(!action.enabled)
    .accessibilityLabel(action.title)
    .accessibilityValue(action.count ?? "")
    .accessibilityAddTraits(action.selected ? .isSelected : [])
    .accessibilityIdentifier("piliplus.glass.\(action.id)")
  }

  var body: some View {
    GlassEffectContainer(spacing: 8) {
      VStack(spacing: 12) {
        if model.state.visible {
          VStack(spacing: 0) {
            ForEach(Array(model.state.commands.enumerated()), id: \.offset) { index, action in
              control(action, union: "commands", glassID: "command-\(index)")
            }
          }
          if let fullscreen = model.state.fullscreen {
            control(fullscreen, union: "fullscreen", glassID: "fullscreen")
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

/// Persistent hosted content preserves SwiftUI's glass IDs and press state
/// across scroll updates. Empty slots pass touches through to the Flutter page.
@available(iOS 26.0, *)
private final class DuoGlassHost: UIView {
  let model = DuoGlassModel()
  private var hostingContent: UIView?
  private var appearanceGeneration = 0
  private var pendingAppearance: (state: DuoGlassState, generation: Int, completion: (() -> Void)?)?
  private var appearanceLink: CADisplayLink?
  private var hiddenFramePresented = false
  var hasPendingAppearance: Bool { pendingAppearance != nil }

  /// A hidden toolbar item detaches its custom view. Reattach an empty glass
  /// container before starting SwiftUI's insertion, otherwise it first renders
  /// already visible. The display clock commits a hidden frame, not a guessed
  /// time delay. Every new request invalidates older animation completions.
  func updateStandalone(_ value: DuoGlassState, animated: Bool, reattaching: Bool = false,
    completion: (() -> Void)? = nil) {
    appearanceGeneration += 1
    let generation = appearanceGeneration
    stopAppearanceClock()
    pendingAppearance = nil
    if value.visible && (!model.state.visible || (reattaching && window == nil))
      && animated && !UIAccessibility.isReduceMotionEnabled {
      var hidden = value
      hidden.visible = false
      model.update(hidden, animated: false)
      pendingAppearance = (value, generation, completion)
      startAppearanceClock()
    } else {
      model.update(value, animated: animated) { [weak self] in
        guard self?.appearanceGeneration == generation else { return }
        completion?()
      }
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { stopAppearanceClock() }
    else { startAppearanceClock() }
  }

  private func startAppearanceClock() {
    guard window != nil, pendingAppearance != nil, appearanceLink == nil else { return }
    setNeedsLayout()
    let target = DuoRailDisplayLinkTarget()
    target.tick = { [weak self] in
      guard let self else { return }
      guard self.window != nil, !self.bounds.isEmpty else {
        self.stopAppearanceClock()
        return
      }
      self.layoutIfNeeded()
      self.hostingContent?.layoutIfNeeded()
      guard self.hiddenFramePresented else {
        self.hiddenFramePresented = true
        return
      }
      let pending = self.pendingAppearance
      self.pendingAppearance = nil
      self.stopAppearanceClock()
      guard let pending, pending.generation == self.appearanceGeneration else { return }
      self.model.update(pending.state, animated: true) { [weak self] in
        guard self?.appearanceGeneration == pending.generation else { return }
        pending.completion?()
      }
    }
    let link = CADisplayLink(target: target, selector: #selector(DuoRailDisplayLinkTarget.refresh))
    link.add(to: .main, forMode: .common)
    appearanceLink = link
  }

  private func stopAppearanceClock() {
    appearanceLink?.invalidate()
    appearanceLink = nil
    hiddenFramePresented = false
  }

  deinit { appearanceLink?.invalidate() }

  func install() {
    guard hostingContent == nil else { return }
    // UIHostingConfiguration embeds SwiftUI content without adding a child to
    // UINavigationController's managed stack or changing topViewController.
    let content = UIHostingConfiguration { DuoGlassControls(model: model).ignoresSafeArea() }
      .margins(.all, 0).makeContentView()
    content.backgroundColor = .clear
    content.clipsToBounds = false
    addSubview(content)
    content.frame = bounds
    content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    hostingContent = content
    clipsToBounds = false
  }
  override var intrinsicContentSize: CGSize {
    CGSize(width: 44, height: model.state.commands.reduce(CGFloat.zero) { $0 + $1.height } + (model.state.fullscreen == nil ? 0 : 56))
  }
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let state = model.state
    guard state.visible, state.enabled, point.x >= 0, point.x <= 44 else { return false }
    let height = state.commands.reduce(CGFloat.zero) { $0 + $1.height }
    if point.y >= 0 && point.y <= height { return true }
    return state.fullscreen != nil && point.y >= height + 12 && point.y <= height + 56
  }
}

@available(iOS 26.0, *)
final class NativePageNavigationController: UINavigationController {
  var onInteractionBlockChanged: ((Bool) -> Void)?
  private var modalOverlayVisible = false
  private var keyboardVisible = false
  private var keyboardObservers = [NSObjectProtocol]()
  private var interactionBlocked: Bool { modalOverlayVisible || keyboardVisible }
  var onHome: ((@escaping () -> Void) -> Void)?
  var onBack: ((@escaping () -> Void) -> Void)?
  var onPageAction: ((Int, String, @escaping () -> Void) -> Void)?
  var onCommentAction: ((Int, @escaping () -> Void) -> Void)?
  var onCommentVisibilityChange: ((Int, Bool) -> Void)?
  var onVisibilityChange: ((Bool, Bool, Bool, Bool) -> Void)?

  private var canGoBack = false
  private var playerFullScreen = false
  private var actionsOwner = 0
  private var pageActions: [[String: Any]] = []
  private var pageBackOnly = true
  private var displayedBackOnly = false
  private var videoChrome: [String: Any]?
  private var videoNavigationEnabled = false
  private var backInFlight = false
  private var pendingActions = Set<String>()
  private var barsVisible = false
  private var backButtonVisible = false
  private var actionsVisible = false
  private var needsItemsUpdate = true
  private var homeToolsRequested = false
  private var homeToolsVisible = false
  private var renderedOwner = 0
  private var updatingBars = false
  private var commentOwner = 0
  private var commentRequested = false
  private var commentLabel = "发表评论"
  private var commentVisible = false
  private var renderedCommentOwner = 0
  private var commentInFlight = false
  private let flutterSurface = DuoFlutterSurfaceView()
  private var placementAnimator: UIViewPropertyAnimator?
  private var placementTarget: CGPoint?
  private var fullscreenRequestedVisible = false
  private var displayedDetailCommands: Bool?
  private var displayedGroupHeight: CGFloat = 0
  private let outerVideoButtons = UIStackView()
  private let navigationAnchor = DuoNavigationAnchorView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
  private var outerButtonsVisible = false
  private var placementLink: CADisplayLink?
  private var lastPresentedAnchor: CGRect?
  private var lastVideoBottom: Double?
  private var itemCache: [String: (NSDictionary, Int, UIBarButtonItem)] = [:]
  private var navigationUpdateDepth = 0
  private var leadingSignature: [[ObjectIdentifier]] = []
  private var railTransition: DuoRailTransition?
  private var lastRailTransitionID = 0
  private var transitionViewport = CGSize.zero
  private var transitionDockY: CGFloat?
  private var transitionPlacementY: CGFloat?
  private var transitionHasFullscreen = false
  private var rootActionsOwner = 0
  private var rootActions: [[String: Any]] = []
  private let glassCommands = DuoGlassHost(frame: CGRect(x: 0, y: 0, width: 44, height: 144))
  private var statsHost: DuoGlassHost?
  private var statsItem: UIBarButtonItem?
  private var statsOwner = 0
  private lazy var anchorItem: UIBarButtonItem = {
    let item = UIBarButtonItem(customView: navigationAnchor)
    item.hidesSharedBackground = true
    item.sharesBackground = false
    item.accessibilityElementsHidden = true
    if #available(iOS 27.0, *) { item.isPaddingRemoved = true; item.visibilityPriority = .high }
    if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
    return item
  }()

  func performNavigationUpdates(_ updates: () -> Void) {
    navigationUpdateDepth += 1
    updates()
    navigationUpdateDepth -= 1
    updateBars()
  }
  private var cachedCommentItem: (Int, String, UIBarButtonItem)?
  private var renderedOuterVideo = false

  override func viewDidLoad() {
    super.viewDidLoad()
    keyboardObservers.append(NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] event in
      guard let self, let window = self.view.window,
        let frame = event.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
      let windowFrame = window.convert(frame, from: window.screen.coordinateSpace)
      let local = self.view.convert(windowFrame, from: window)
      self.setKeyboardVisible(self.view.bounds.intersection(local).height > 1)
    })
    keyboardObservers.append(NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
      self?.setKeyboardVisible(false)
    })
    navigationBar.isTranslucent = true
    toolbar.isTranslucent = true
    setNavigationBarHidden(true, animated: false)
    setToolbarHidden(true, animated: false)
    flutterSurface.isOpaque = false
    flutterSurface.backgroundColor = .clear
    flutterSurface.accessibilityIdentifier = "piliplus.page.surface"
    view.addSubview(flutterSurface)
    outerVideoButtons.isHidden = true
    outerVideoButtons.alpha = 1
    outerVideoButtons.axis = .vertical
    outerVideoButtons.alignment = .center
    outerVideoButtons.spacing = 12
    // Position the stack by its top edge. Removing the independent fullscreen
    // slot must not cancel/restart the shared group's return animation.
    outerVideoButtons.layer.anchorPoint = CGPoint(x: 0.5, y: 0)
    view.addSubview(outerVideoButtons)
    navigationAnchor.accessibilityIdentifier = "piliplus.navigation.anchor"
    navigationAnchor.alpha = 0
    navigationAnchor.isUserInteractionEnabled = false
    navigationAnchor.accessibilityElementsHidden = true
    navigationAnchor.widthAnchor.constraint(equalToConstant: 44).isActive = true
    navigationAnchor.heightAnchor.constraint(equalToConstant: 44).isActive = true
    navigationAnchor.geometryChanged = { [weak self] in self?.view.setNeedsLayout() }
    prepareSharedNavigationGroup()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updateBars()
  }

  func setKeyboardVisible(_ visible: Bool) {
    guard keyboardVisible != visible else { return }
    keyboardVisible = visible
    needsItemsUpdate = true
    onInteractionBlockChanged?(interactionBlocked)
    updateBars()
  }

  func setModalOverlayVisible(_ visible: Bool) {
    guard modalOverlayVisible != visible else { return }
    modalOverlayVisible = visible
    needsItemsUpdate = true
    onInteractionBlockChanged?(interactionBlocked)
    updateBars()
  }

  func setCommentAction(owner: Int, visible: Bool, label: String) {
    if commentOwner != owner || commentRequested != visible || commentLabel != label {
      needsItemsUpdate = true
    }
    commentOwner = owner
    commentRequested = visible
    commentLabel = label
    updateBars()
  }

  func setPageState(canGoBack: Bool, fullScreen: Bool) {
    self.canGoBack = canGoBack
    playerFullScreen = fullScreen
    updateBars()
  }

  func setPageActions(owner: Int, items: [[String: Any]], video: [String: Any]? = nil,
    homeTools: Bool = false, canGoBack: Bool? = nil, backOnly: Bool = true) {
    // A non-video page cannot acquire Home from an absent or stale flag.
    let backOnly = backOnly || video == nil
    if pageBackOnly != backOnly { needsItemsUpdate = true }
    pageBackOnly = backOnly
    if actionsOwner != owner || homeToolsRequested != homeTools ||
      !NSArray(array: pageActions).isEqual(to: items) { needsItemsUpdate = true }
    if let canGoBack { self.canGoBack = canGoBack }
    actionsOwner = owner
    if homeTools {
      rootActionsOwner = owner
      rootActions = items.filter { ["search", "notifications"].contains($0["id"] as? String ?? "") }
    }
    pageActions = items
    videoChrome = video
    homeToolsRequested = homeTools
    updateBars()
  }

  private var hasVerticalBar: Bool {
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        return traitCollection.verticalBarEdge != .unspecified
      }
    #endif
    return false
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateFlutterSurface()

    updateBars()
  }

  private func updateFlutterSurface() {
    guard isViewLoaded else { return }
    let raised = hasVerticalBar && (canGoBack || railTransition != nil)
    flutterSurface.isHidden = !raised
    flutterSurface.isUserInteractionEnabled = raised
    guard let tabs = viewControllers.first as? NativeTabBarController else { return }
    // Raise only inside tab content. UIKit's navigation command container is
    // outside this controller and must remain above the actual page surface.
    if flutterSurface.superview !== tabs.view { tabs.view.addSubview(flutterSurface) }
    flutterSurface.frame = tabs.view.bounds
    tabs.setFlutterSurface(raised ? flutterSurface : nil)
    if raised {
      tabs.view.bringSubviewToFront(flutterSurface)
      view.bringSubviewToFront(navigationBar)
      view.bringSubviewToFront(toolbar)
      view.bringSubviewToFront(outerVideoButtons)
    }
  }

  private var freezesReturnCommands: Bool {
    railTransition?.returning == true && (railTransition?.interactive == true || railTransition?.committed == nil)
      && hasVerticalBar && barsVisible
      && !interactionBlocked && !playerFullScreen
  }

  private var returningToRoot: Bool {
    railTransition?.returning == true && railTransition?.interactive == false
      && railTransition?.committed == true && railTransition?.destinationSecondary == 0
  }

  private var enteringPage: Bool { railTransition.map { !$0.returning } ?? false }

  private var commandSecondary: CGFloat {
    if let state = railTransition, state.returning, !state.interactive,
      state.committed != nil, let destination = state.destinationSecondary { return destination }
    return railTransition?.secondary ?? (canGoBack ? 1 : 0)
  }

  private func updateBars() {
    guard navigationUpdateDepth == 0, !updatingBars, isViewLoaded, let content = topViewController else { return }
    updatingBars = true
    defer { updatingBars = false }
    updateFlutterSurface()
    toolbar.isUserInteractionEnabled = railTransition == nil && !interactionBlocked
    if freezesReturnCommands {
      // Hold the complete rail while the finger controls the page, or while
      // the gesture recognizer has not decided whether to pop or cancel.
      glassCommands.isUserInteractionEnabled = false
      glassCommands.accessibilityElementsHidden = true
      return
    }
    let managesVideo = !interactionBlocked && videoChrome != nil && !playerFullScreen
      && !(videoChrome?["fullScreen"] as? Bool ?? false) && hasVerticalBar && canGoBack
    let isHomeTools = homeToolsRequested && !canGoBack
    // Root tools cannot masquerade as detail-page actions during a route change.
    let pageAllowed = canGoBack && !homeToolsRequested && !returningToRoot
    let visible = hasVerticalBar && !interactionBlocked && !playerFullScreen && !(videoChrome?["fullScreen"] as? Bool ?? false)
    let screenSize = view.window?.windowScene?.screen.bounds.size ?? .zero
    let innerDisplay = (content as? NativeTabBarController)?.isInnerDisplay
      ?? (min(screenSize.width, screenSize.height) >= 600)
    let outerVideo = managesVideo && !innerDisplay
    let showsBack = visible && canGoBack && (!outerVideo || videoChrome?["frame"] != nil)
    let showsComment = visible && commentRequested && commentOwner != 0 && !returningToRoot
    let toolbarActions = homeToolsRequested ? [] : pageActions.filter {
      !["home", "fullscreen"].contains($0["id"] as? String ?? "")
    }
    let home = pageActions.first { ($0["id"] as? String) == "home" }
    let fullscreen = pageActions.first { ($0["id"] as? String) == "fullscreen" }
    let hasToolbarCommands = visible && pageAllowed && !toolbarActions.isEmpty
    let showsActions = visible && pageAllowed && toolbarActions.contains { $0["hidden"] as? Bool != true }
    let showsHome = visible && isHomeTools
    let showsToolbar = showsActions || showsComment
    let animate = !interactionBlocked && view.window != nil && !UIAccessibility.isReduceMotionEnabled
      && (needsItemsUpdate || actionsOwner != renderedOwner || visible != barsVisible
        || showsHome != homeToolsVisible || showsActions != actionsVisible
        || showsBack != backButtonVisible)
    do { // Compare desired commands with UIKit on every layout; HDR can rebuild its bars.
      needsItemsUpdate = false
      content.navigationItem.hidesBackButton = true
      content.navigationItem.leftItemsSupplementBackButton = false
      let showsSharedGroup = visible && (showsHome || showsBack || railTransition != nil)
      let leadingItems: [[UIBarButtonItem]] = showsSharedGroup ? [[anchorItem]] : []
      updateSharedNavigationGroup(home: home, fullscreen: fullscreen)

      let signature = leadingItems.map { $0.map(ObjectIdentifier.init) }
      let realized = content.navigationItem.leadingItemGroups.map { $0.barButtonItems.map(ObjectIdentifier.init) }
      if signature != leadingSignature || realized != signature {
        leadingSignature = signature
        content.navigationItem.leadingItemGroups = leadingItems.map {
          .fixedGroup(representativeItem: nil, items: $0)
        }
      }
      var items = hasToolbarCommands ? makeToolbarItems(toolbarActions, owner: actionsOwner) : []
      if showsComment { items.append(makeCommentItem()) }
      let previous = (content.toolbarItems ?? []).filter { $0.identifier != "piliplus.toolbar.space" }
      if previous.map(ObjectIdentifier.init) != items.map(ObjectIdentifier.init) {
        let space = UIBarButtonItem(systemItem: .flexibleSpace)
        space.identifier = "piliplus.toolbar.space"
        content.setToolbarItems(items.isEmpty ? nil : [space] + items, animated: animate)
      }
      #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
          content.navigationItem.verticalBarCompressionBehavior = .prefersBarItems
        }
      #endif
    }
    let changed = visible != barsVisible || showsActions != actionsVisible
      || managesVideo != videoNavigationEnabled || showsHome != homeToolsVisible
      || showsBack != backButtonVisible
    renderedOwner = actionsOwner
    barsVisible = visible
    backButtonVisible = showsBack
    actionsVisible = showsActions
    videoNavigationEnabled = managesVideo
    homeToolsVisible = showsHome
    renderedOuterVideo = outerVideo
    let navigationVisible = visible
    if isNavigationBarHidden == navigationVisible {
      setNavigationBarHidden(!navigationVisible, animated: false)
    }
    if isToolbarHidden == showsToolbar {
      setToolbarHidden(!showsToolbar, animated: animate)
    }
    updateOuterVideoButtons(visible: visible && (showsHome || showsBack || railTransition != nil))
    if showsComment != commentVisible || renderedCommentOwner != commentOwner {
      commentVisible = showsComment
      renderedCommentOwner = commentOwner
      onCommentVisibilityChange?(commentOwner, showsComment)
    }
    if changed { onVisibilityChange?(showsBack, showsActions, managesVideo, showsHome) }
  }

  private func requestBack() {
    guard barsVisible, canGoBack, railTransition == nil, !interactionBlocked, !backInFlight else { return }
    backInFlight = true
    onBack? { [weak self] in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        self?.backInFlight = false
      }
    }
  }

  private func trackSystemNavigation(_ enabled: Bool) {
    if !enabled {
      placementLink?.invalidate()
      placementLink = nil
      lastPresentedAnchor = nil
      stopPlacementAnimation()
      return
    }
    guard placementLink == nil else { return }
    let target = DuoRailDisplayLinkTarget()
    target.tick = { [weak self] in
      guard let self, self.navigationAnchor.window != nil else { return }
      let frame: CGRect
      if let source = self.navigationAnchor.layer.presentation(), let destination = self.view.layer.presentation() {
        frame = source.convert(self.navigationAnchor.bounds, to: destination)
      } else {
        frame = self.navigationAnchor.convert(self.navigationAnchor.bounds, to: self.view)
      }
      // Observe only UIKit's moving safe-area anchor. UIKit animates position;
      // there is no application-side spring integrator or per-frame layout.
      if self.lastPresentedAnchor != frame {
        self.lastPresentedAnchor = frame
        self.updateOuterVideoButtons(visible: true, presentedAnchor: frame)
      }
    }
    let link = CADisplayLink(target: target, selector: #selector(DuoRailDisplayLinkTarget.refresh))
    let maximum = Float(view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
    link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
    link.add(to: .main, forMode: .common)
    placementLink = link
  }

  private func stopPlacementAnimation() {
    guard let animator = placementAnimator else { return }
    let current = outerVideoButtons.layer.presentation()?.position ?? outerVideoButtons.layer.position
    animator.stopAnimation(true)
    placementAnimator = nil
    placementTarget = nil
    UIView.performWithoutAnimation { self.outerVideoButtons.layer.position = current }
  }

  private func placeCommandGroup(at center: CGPoint, immediately: Bool) {
    if immediately {
      stopPlacementAnimation()
      UIView.performWithoutAnimation { self.outerVideoButtons.layer.position = center }
      placementTarget = center
      return
    }
    guard placementTarget != center else { return }
    stopPlacementAnimation()
    placementTarget = center
    guard abs(outerVideoButtons.layer.position.y - center.y) > 0.25 || abs(outerVideoButtons.layer.position.x - center.x) > 0.25 else {
      outerVideoButtons.layer.position = center
      return
    }
    let animator = UIViewPropertyAnimator(duration: 0.22,
      timingParameters: UISpringTimingParameters())
    animator.addAnimations { self.outerVideoButtons.layer.position = center }
    animator.addCompletion { [weak self, weak animator] _ in
      guard let self, self.placementAnimator === animator else { return }
      self.placementAnimator = nil
    }
    placementAnimator = animator
    animator.startAnimation()
  }

  deinit {
    placementLink?.invalidate()
    keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
  }

  private func setOuterButtonsVisible(_ visible: Bool) {
    guard outerButtonsVisible != visible else { return }
    outerButtonsVisible = visible
    trackSystemNavigation(visible)
    // Keep the native host alive, transparent and unscaled. Conditional glass
    // views materialize/dematerialize inside the persistent native container.
    outerVideoButtons.isHidden = false
    outerVideoButtons.isUserInteractionEnabled = visible
    var state = glassCommands.model.state
    state.visible = visible
    glassCommands.model.update(state, animated: view.window != nil && !playerFullScreen)
  }

  private func updateOuterVideoButtons(visible: Bool, presentedAnchor: CGRect? = nil) {
    // The display-link anchor observer must obey the same return hold as the
    // page/toolbar updates; otherwise it can move the group during a swipe.
    if freezesReturnCommands { return }
    if enteringPage && renderedOuterVideo && videoChrome?["frame"] == nil { return }
    guard visible, navigationAnchor.window == view.window, navigationAnchor.window != nil,
      !navigationAnchor.bounds.isEmpty else { setOuterButtonsVisible(false); return }
    let bounds = view.bounds
    let rail = max(72, max(view.safeAreaInsets.right, topViewController?.view.safeAreaInsets.right ?? 0))
    let anchorFrame = presentedAnchor ?? navigationAnchor.convert(navigationAnchor.bounds, to: view)
    let secondary = commandSecondary
    var dockY = anchorFrame.minY
    var videoBottom: Double?
    if renderedOuterVideo, let frame = videoChrome?["frame"] as? [String: Double],
      let bottom = frame["bottom"], let right = frame["right"], bottom.isFinite, right.isFinite,
      frame["aspect"].map({ abs($0 - bounds.width / max(1, bounds.height)) <= 0.03 }) ?? true {
      videoBottom = bottom
      if right * bounds.width > bounds.width - rail { dockY = max(dockY, bottom * bounds.height + 8) }
    }
    if let transition = railTransition {
      if transitionViewport != bounds.size {
        transitionViewport = bounds.size
        transitionDockY = dockY
      }
      if !transition.returning {
        transitionDockY = max(transitionDockY ?? dockY, dockY)
        dockY = max(anchorFrame.minY, transitionDockY ?? dockY)
      } else if transition.committed != true || transition.interactive {
        dockY = max(anchorFrame.minY, transitionDockY ?? dockY)
      }
    }
    // Keep below the system's actual moving anchor (including expanded island).
    let y = anchorFrame.minY + (dockY - anchorFrame.minY) * DuoRailMotion.dock(secondary)
    // Released returns use the confirmed destination, while held gestures
    // remain frozen above. Cancellation keeps the outgoing detail controls.
    // Entering commands belong to the destination from progress zero. The
    // existing committed/held/cancelled return policy remains unchanged.
    let detailCommands = enteringPage || secondary >= 0.7
    updateCommandRoles(detail: detailCommands, backOnly: detailCommands && pageBackOnly)
    let rootHeight: CGFloat = rootActions.contains { $0["id"] as? String == "notifications" } ? 88 : 44
    let height: CGFloat = detailCommands ? (displayedBackOnly ? 44 : 88) : rootHeight
    displayedGroupHeight = height
    glassCommands.isUserInteractionEnabled = railTransition == nil
    glassCommands.accessibilityElementsHidden = railTransition != nil
    let hasFullscreen = returningToRoot ? false : (railTransition == nil || railTransition?.returning == true
      ? pageActions.contains { $0["id"] as? String == "fullscreen" } : transitionHasFullscreen)
    fullscreenRequestedVisible = hasFullscreen && detailCommands
    publishCommandGlass(detail: detailCommands, backOnly: displayedBackOnly)
    // Fixed host bounds leave room for outgoing glass to dematerialize. The
    // renderer owns visible geometry, so removing a row never clips an exit.
    let totalHeight: CGFloat = 144
    let followsFinger = railTransition?.interactive ?? false
    // Only placement waits for the route to settle. Native glass, symbols and
    // independent controls retain their existing transition timing.
    let destinationY: CGFloat
    if railTransition != nil, let heldY = transitionPlacementY { destinationY = heldY }
    else if returningToRoot { destinationY = anchorFrame.minY }
    else if railTransition != nil, !followsFinger { destinationY = dockY }
    else { destinationY = y }
    let x = bounds.width - max(48, rail / 2) - 22
    if outerVideoButtons.bounds.size != CGSize(width: 44, height: totalHeight) {
      UIView.performWithoutAnimation {
        self.outerVideoButtons.bounds.size = CGSize(width: 44, height: totalHeight)
        self.outerVideoButtons.layoutIfNeeded()
      }
    }
    let placementY = railTransition != nil ? destinationY : max(anchorFrame.minY, destinationY)
    placeCommandGroup(at: CGPoint(x: x + 22, y: placementY),
      immediately: !outerButtonsVisible || railTransition != nil
        || (presentedAnchor != nil && placementAnimator == nil) || UIAccessibility.isReduceMotionEnabled)
    lastVideoBottom = videoBottom

    setOuterButtonsVisible(true)
    view.bringSubviewToFront(outerVideoButtons)
  }

  func setRailTransition(_ state: DuoRailTransition) {
    guard state.id >= lastRailTransitionID else { return }
    if state.id != lastRailTransitionID || railTransition == nil {
      lastRailTransitionID = state.id
      transitionViewport = view.bounds.size
      // Capture the *displayed* detail location before Dart changes page owners.
      transitionDockY = state.returning ? (outerVideoButtons.layer.presentation()?.frame.minY ?? outerVideoButtons.frame.minY) : nil
      transitionHasFullscreen = pageActions.contains { $0["id"] as? String == "fullscreen" }
      stopPlacementAnimation()
      transitionPlacementY = outerButtonsVisible ? outerVideoButtons.layer.position.y : nil
      if state.active && state.returning {
        glassCommands.isUserInteractionEnabled = false
      }
    }
    railTransition = state.active ? state : nil
    if !state.active {
      transitionDockY = nil
      transitionPlacementY = nil
    }
    updateBars()
  }

  private func prepareSharedNavigationGroup() {
    glassCommands.accessibilityIdentifier = "piliplus.navigation.group"
    glassCommands.widthAnchor.constraint(equalToConstant: 44).isActive = true
    glassCommands.heightAnchor.constraint(equalToConstant: 144).isActive = true
    glassCommands.install()
    outerVideoButtons.addArrangedSubview(glassCommands)
    glassCommands.model.onAction = { [weak self] id in
      guard let self else { return }
      if id == "back" { self.requestBack() }
      else if ["home", "fullscreen"].contains(id) { self.requestNavigationCommand(id) }
      else { self.requestRootTool(id) }
    }
  }

  private func updateCommandRoles(detail: Bool, backOnly: Bool) {
    displayedDetailCommands = detail
    displayedBackOnly = backOnly
  }

  private func publishCommandGlass(detail: Bool, backOnly: Bool) {
    let notifications = rootActions.first { $0["id"] as? String == "notifications" }
    let home = pageActions.first { $0["id"] as? String == "home" }
    let fullscreen = pageActions.first { $0["id"] as? String == "fullscreen" }
    var commands: [DuoGlassAction]
    if detail {
      commands = [DuoGlassAction(id: "back", symbol: "chevron.backward", title: "返回")]
      if !backOnly {
        commands.append(DuoGlassAction(id: "home", symbol: "house", title: "返回主页",
          enabled: home?["enabled"] as? Bool ?? true))
      }
    } else {
      commands = [DuoGlassAction(id: "search", symbol: "magnifyingglass", title: "搜索")]
      if notifications != nil {
        commands.append(DuoGlassAction(id: "notifications", symbol: "envelope", title: "私信",
          enabled: notifications?["enabled"] as? Bool ?? true, badge: notifications?["badge"] as? String))
      }
    }
    let value = DuoGlassState(commands: commands,
      fullscreen: fullscreenRequestedVisible ? DuoGlassAction(id: "fullscreen", symbol: "arrow.up.left.and.arrow.down.right",
        title: "全屏", enabled: fullscreen?["enabled"] as? Bool ?? true) : nil,
      visible: true, enabled: railTransition == nil)
    glassCommands.model.update(value, animated: outerButtonsVisible && view.window != nil)
  }

  private func updateSharedNavigationGroup(home: [String: Any]?, fullscreen: [String: Any]?) {
    if railTransition != nil && canGoBack && fullscreen != nil { transitionHasFullscreen = true }
  }

  private func requestRootTool(_ id: String) {
    guard barsVisible, !canGoBack, railTransition == nil, !interactionBlocked else { return }
    onPageAction?(rootActionsOwner, id, {})
  }

  private func requestNavigationCommand(_ id: String) {
    guard barsVisible, canGoBack, railTransition == nil, !interactionBlocked else { return }
    if pageActions.contains(where: { $0["id"] as? String == id && ($0["enabled"] as? Bool ?? true) }) {
      let key = "\(actionsOwner):\(id)"
      guard pendingActions.insert(key).inserted else { return }
      onPageAction?(actionsOwner, id) { [weak self] in self?.pendingActions.remove(key) }
    } else if id == "home", !backInFlight {
      backInFlight = true
      onHome? { [weak self] in self?.backInFlight = false }
    }
  }

  private func makeCommentItem() -> UIBarButtonItem {
    if let cached = cachedCommentItem, cached.0 == commentOwner, cached.1 == commentLabel { return cached.2 }
    let owner = commentOwner
    let descriptor: [String: Any] = ["id": "compose", "title": commentLabel]
    let handler: UIActionHandler = { [weak self] _ in
      guard let self, self.commentVisible, self.commentOwner == owner, !self.commentInFlight else { return }
      self.commentInFlight = true
      self.onCommentAction?(owner) { [weak self] in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.commentInFlight = false }
      }
    }
    let image = UIImage(systemName: "square.and.pencil")
    let item: UIBarButtonItem
    if let cached = cachedCommentItem, cached.1 == commentLabel {
      item = cached.2
      rebind(item, action: UIAction(title: commentLabel, image: image, handler: handler), handler: handler)
      if enteringPage, let host = item.customView as? DuoGlassHost, host.window == nil {
        host.updateStandalone(host.model.state, animated: true, reattaching: true)
      }
    } else {
      item = makeHomeToolItem(descriptor, image: image, handler: handler, animateAppearance: enteringPage)
    }
    item.identifier = "piliplus.comment.compose"
    cachedCommentItem = (owner, commentLabel, item)
    if #available(iOS 27.0, *) { item.visibilityPriority = .high }
    if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
    return item
  }

  private weak var avatarItem: UIBarButtonItem?
  /// Side of the avatar photo in points; Dart asks for a 120px image to match.
  private static let avatarSide: CGFloat = 38

  private var avatarURL: String?
  private var avatarTask: URLSessionDataTask?
  private func loadAvatar(_ url: String, into item: UIBarButtonItem, placeholder: String?) {
    avatarItem = item
    guard url != avatarURL else { return }
    cancelAvatar()
    avatarURL = url
    if item.image == nil, let placeholder { item.image = UIImage(systemName: placeholder) }
    guard let source = URL(string: url) else { return }
    avatarTask = URLSession.shared.dataTask(with: source) { [weak self, weak item] data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      // Nearly fills the round glass button (about 48pt), leaving a thin ring,
      // so the photo reads as large as the search and notification icons.
      let size = CGSize(width: Self.avatarSide, height: Self.avatarSide)
      let circle = UIGraphicsImageRenderer(size: size).image { _ in
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
        // Fill the circle, cropping the longer side.
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(
          x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
          width: drawn.width, height: drawn.height))
      }.withRenderingMode(.alwaysOriginal)
      DispatchQueue.main.async {
        guard let self, self.avatarURL == url else { return }
        item?.image = circle
      }
    }
    avatarTask?.resume()
  }

  private func cancelAvatar() {
    avatarTask?.cancel()
    avatarTask = nil
    avatarURL = nil
  }


  private func glassAction(_ descriptor: [String: Any]) -> DuoGlassAction {
    let id = descriptor["id"] as? String ?? ""
    let selected = descriptor["selected"] as? Bool ?? false
    let symbol: String
    switch id {
    case "search": symbol = "magnifyingglass"
    case "notifications": symbol = "envelope"
    case "home": symbol = "house"
    case "fullscreen": symbol = "arrow.up.left.and.arrow.down.right"
    case "mine": symbol = "person.crop.circle"
    case "like": symbol = selected ? "hand.thumbsup.fill" : "hand.thumbsup"
    case "comment": symbol = "bubble.right"
    case "repost": symbol = "arrowshape.turn.up.right"
    case "share": symbol = "square.and.arrow.up"
    case "reply": symbol = "arrowshape.turn.up.left.fill"
    case "compose": symbol = "square.and.pencil"
    case "scrollToTop": symbol = "arrow.up.to.line"
    default: symbol = "ellipsis"
    }
    return DuoGlassAction(id: id, symbol: descriptor["symbol"] as? String ?? symbol,
      title: descriptor["title"] as? String ?? "", count: descriptor["count"] as? String,
      enabled: descriptor["enabled"] as? Bool ?? true, selected: selected,
      color: selected ? (descriptor["selectedColor"] as? Int).map(Self.color(argb:)) ?? .tintColor : .label,
      badge: descriptor["badge"] as? String)
  }

  private func actionHandler(id: String, owner: Int) -> UIActionHandler {
    { [weak self] _ in
      guard let self, self.barsVisible, self.actionsOwner == owner,
        self.railTransition == nil, !self.interactionBlocked else { return }
      let key = "\(owner):\(id)"
      guard self.pendingActions.insert(key).inserted else { return }
      self.onPageAction?(owner, id) { [weak self] in self?.pendingActions.remove(key) }
    }
  }

  private func makeToolbarItems(_ descriptors: [[String: Any]], owner: Int) -> [UIBarButtonItem] {
    let grouped = descriptors.filter { $0["count"] != nil || ["like", "comment", "repost", "share"].contains($0["id"] as? String ?? "") }
    let groupedIDs = Set(grouped.compactMap { $0["id"] as? String })
    var result = [UIBarButtonItem]()
    var inserted = false
    for descriptor in descriptors {
      let id = descriptor["id"] as? String ?? ""
      if groupedIDs.contains(id) {
        guard !inserted else { continue }
        inserted = true
        if statsHost == nil {
          let host = DuoGlassHost()
          host.install()
          host.widthAnchor.constraint(equalToConstant: 44).isActive = true
          statsHost = host
          let item = UIBarButtonItem(customView: host)
          item.identifier = "piliplus.actions.glassGroup"
          item.hidesSharedBackground = true
          item.sharesBackground = false
          if #available(iOS 27.0, *) { item.isPaddingRemoved = true }
          if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
          statsItem = item
        }
        guard let host = statsHost, let item = statsItem else { continue }
        let actions = grouped.filter { $0["hidden"] as? Bool != true }.map(glassAction)
        let height = actions.reduce(CGFloat.zero) { $0 + $1.height }
        if host.frame.size != CGSize(width: 44, height: height) {
          host.frame.size = CGSize(width: 44, height: height)
          host.invalidateIntrinsicContentSize()
        }
        let changed = host.model.state.commands != actions || statsOwner != owner
        if changed {
          host.model.onAction = { [weak self] id in self?.actionHandler(id: id, owner: owner)(UIAction { _ in }) }
          let state = DuoGlassState(commands: actions, visible: true)
          if enteringPage && host.window == nil {
            host.updateStandalone(state, animated: true, reattaching: true)
          } else {
            host.model.update(state, animated: host.window != nil)
          }
          host.invalidateIntrinsicContentSize()
          item.menuRepresentation = UIMenu(title: "页面操作", children: grouped.map { descriptor in
            let action = glassAction(descriptor)
            return UIAction(title: action.title, image: UIImage(systemName: action.symbol),
              attributes: action.enabled ? [] : [.disabled], handler: actionHandler(id: action.id, owner: owner))
          })
          statsOwner = owner
        }
        result.append(item)
      } else { result.append(makeActionItem(descriptor, owner: owner)) }
    }
    return result
  }

  private func makeActionItem(_ descriptor: [String: Any], owner: Int) -> UIBarButtonItem {
    let id = descriptor["id"] as? String ?? ""
    let signature = NSDictionary(dictionary: descriptor)
    let action = glassAction(descriptor)
    let handler = actionHandler(id: id, owner: owner)
    let image = UIImage(systemName: action.symbol)
    let menu = UIAction(title: action.title, image: image, handler: handler)
    if let cached = itemCache[id], cached.0 == signature {
      if cached.1 != owner { rebind(cached.2, action: menu, handler: handler) }
      if enteringPage, let host = cached.2.customView as? DuoGlassHost,
        host.window == nil, !host.hasPendingAppearance {
        host.updateStandalone(host.model.state, animated: true, reattaching: true)
      }
      itemCache[id] = (signature, owner, cached.2)
      return cached.2
    }
    if let cached = itemCache[id] {
      let item = cached.2
      rebind(item, action: menu, handler: handler)
      if let host = item.customView as? DuoGlassHost {
        var state = host.model.state
        state.commands = [action]
        state.visible = descriptor["hidden"] as? Bool != true
        // Keep the item slot until the renderer finishes dematerializing. This
        // uses the system animation completion, never an assumed time delay.
        item.isHidden = false
        host.updateStandalone(state, animated: view.window != nil, reattaching: enteringPage) { [weak item, weak host] in
          guard let host, !host.model.state.visible else { return }
          item?.isHidden = true
        }
        host.invalidateIntrinsicContentSize()
      }
      item.isEnabled = action.enabled
      itemCache[id] = (signature, owner, item)
      return item
    }
    // Independent controls use the same native interactive glass renderer,
    // with the system materialize transition and stable toolbar item identity.
    let item = makeHomeToolItem(descriptor, image: image, handler: handler,
      animateAppearance: id == "scrollToTop" || enteringPage)
    item.identifier = "piliplus.action.\(id)"
    item.isHidden = descriptor["hidden"] as? Bool ?? false
    item.isEnabled = action.enabled
    item.sharesBackground = false
    if #available(iOS 27.0, *) { item.visibilityPriority = .high }
    if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
    itemCache[id] = (signature, owner, item)
    return item
  }

  private static func color(argb: Int) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xff) / 255, green: CGFloat((argb >> 8) & 0xff) / 255,
      blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat((argb >> 24) & 0xff) / 255)
  }

  private func rebind(_ item: UIBarButtonItem, action: UIAction, handler: @escaping UIActionHandler) {
    if let host = item.customView as? DuoGlassHost {
      host.model.onAction = { _ in handler(action) }
      item.menuRepresentation = action
    } else { item.primaryAction = action }
  }

  private func makeHomeToolItem(_ descriptor: [String: Any], image: UIImage?,
    handler: @escaping UIActionHandler, animateAppearance: Bool = false) -> UIBarButtonItem {
    let action = glassAction(descriptor)
    let host = DuoGlassHost(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
    host.install()
    host.widthAnchor.constraint(equalToConstant: 44).isActive = true
    host.heightAnchor.constraint(equalToConstant: 44).isActive = true
    host.model.onAction = { _ in handler(UIAction { _ in }) }
    let state = DuoGlassState(commands: [action], visible: descriptor["hidden"] as? Bool != true,
      standalone: true)
    if animateAppearance { host.updateStandalone(state, animated: true) }
    else { host.model.update(state, animated: false) }
    let item = UIBarButtonItem(customView: host)
    item.hidesSharedBackground = true
    item.sharesBackground = false
    if #available(iOS 27.0, *) { item.isPaddingRemoved = true }
    item.title = action.title
    item.accessibilityLabel = action.title
    item.menuRepresentation = UIAction(title: action.title, image: image, handler: handler)
    return item
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
  }
  override var childForStatusBarStyle: UIViewController? { topViewController }
  override var childForStatusBarHidden: UIViewController? { topViewController }
  override var childForHomeIndicatorAutoHidden: UIViewController? { topViewController }
}
