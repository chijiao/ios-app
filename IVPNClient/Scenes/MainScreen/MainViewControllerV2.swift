//
//  MainViewControllerV2.swift
//  IVPNClient
//
//  Created by Juraj Hilje on 19/02/2020.
//  Copyright © 2020 IVPN. All rights reserved.
//

import UIKit
import FloatingPanel
import NetworkExtension

class MainViewControllerV2: UIViewController {
    
    // MARK: - @IBOutlets -
    
    @IBOutlet weak var infoAlertView: InfoAlertView!
    @IBOutlet weak var mapScrollView: MapScrollView?
    
    // MARK: - Properties -
    
    var floatingPanel: FloatingPanelController!
    private var updateServerListDidComplete = false
    private var updateServersTimer = Timer()
    private var infoAlertViewModel = InfoAlertViewModel()
    private let markerContainerView = MapMarkerContainerView()
    private let markerView = MapMarkerView()
    
    // MARK: - @IBActions -
    
    @IBAction func openSettings(_ sender: UIButton) {
        presentSettingsScreen()
        
        if let controlPanelViewController = floatingPanel.contentViewController {
            NotificationCenter.default.removeObserver(controlPanelViewController, name: Notification.Name.TermsOfServiceAgreed, object: nil)
            NotificationCenter.default.removeObserver(controlPanelViewController, name: Notification.Name.NewSession, object: nil)
            NotificationCenter.default.removeObserver(controlPanelViewController, name: Notification.Name.ForceNewSession, object: nil)
        }
    }
    
    @IBAction func openAccountInfo(_ sender: UIButton) {
        guard evaluateIsLoggedIn() else {
            return
        }
        
        presentAccountScreen()
    }
    
    // MARK: - View lifecycle -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initMarker()
        initSettingsAction()
        initFloatingPanel()
        addObservers()
        startServersUpdate()
        initInfoAlert()
        updateInfoAlert()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startPingService(updateServerListDidComplete: updateServerListDidComplete)
        refreshUI()
    }
    
    deinit {
        destoryFloatingPanel()
        removeObservers()
        updateServersTimer.invalidate()
    }
    
    // MARK: - Segues -
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ControlPanelSelectServer" {
            if let navController = segue.destination as? UINavigationController {
                if let viewController = navController.topViewController as? ServerViewController {
                    viewController.serverDelegate = floatingPanel.contentViewController as! ControlPanelViewController
                }
            }
        }
        
        if segue.identifier == "ControlPanelSelectExitServer" {
            if let navController = segue.destination as? UINavigationController {
                if let viewController = navController.topViewController as? ServerViewController {
                    viewController.isExitServer = true
                }
            }
        }
    }
    
    // MARK: - Interface Orientations -
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        refreshUI()
    }
    
    // MARK: - Methods -
    
    func refreshUI() {
        updateFloatingPanelLayout()
        mapScrollView?.setupConstraints()
        markerContainerView.setupConstraints()
    }
    
    func updateStatus(vpnStatus: NEVPNStatus) {
        markerView.status = vpnStatus
    }
    
    func updateGeoLocation() {
        let request = ApiRequestDI(method: .get, endpoint: Config.apiGeoLookup)
        
        ApiService.shared.request(request) { [weak self] (result: Result<GeoLookup>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let model):
                if let controlPanelViewController = self.floatingPanel.contentViewController as? ControlPanelViewController {
                    controlPanelViewController.connectionInfoViewModel = ProofsViewModel(model: model)
                }
            case .failure:
                break
            }
        }
    }
    
    func expandFloatingPanel() {
        floatingPanel.move(to: .full, animated: true)
    }
    
    // MARK: - Observers -
    
    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(updateFloatingPanelLayout), name: Notification.Name.UpdateFloatingPanelLayout, object: nil)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: Notification.Name.UpdateFloatingPanelLayout, object: nil)
    }
    
    // MARK: - Private methods -
    
    @objc private func updateFloatingPanelLayout() {
        floatingPanel.updateLayout()
        markerContainerView.setupConstraints()
        updateInfoAlert()
    }
    
    @objc private func updateServersList() {
        ApiService.shared.getServersList(storeInCache: true) { result in
            self.updateServerListDidComplete = true
            switch result {
            case .success(let serverList):
                Application.shared.serverList = serverList
                Pinger.shared.serverList = Application.shared.serverList
                Pinger.shared.ping()
            default:
                break
            }
        }
    }
    
    private func initMarker() {
        markerContainerView.addSubview(markerView)
        view.addSubview(markerContainerView)
    }
    
    private func initSettingsAction() {
        let settingsButton = UIButton()
        view.addSubview(settingsButton)
        settingsButton.bb.size(width: 42, height: 42).top(55).right(-30)
        settingsButton.setupIcon(imageName: "icon-settings")
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        
        let accountButton = UIButton()
        view.addSubview(accountButton)
        if UIDevice.current.userInterfaceIdiom == .pad {
            accountButton.bb.size(width: 42, height: 42).top(55).right(-100)
        } else {
            accountButton.bb.size(width: 42, height: 42).top(55).left(30)
        }
        accountButton.setupIcon(imageName: "icon-user")
        accountButton.addTarget(self, action: #selector(openAccountInfo), for: .touchUpInside)
    }
    
    private func initInfoAlert() {
        infoAlertView.delegate = infoAlertViewModel
    }
    
    private func updateInfoAlert() {
        if infoAlertViewModel.shouldDisplay {
            infoAlertViewModel.update()
            infoAlertView.show(type: infoAlertViewModel.type, text: infoAlertViewModel.text, actionText: infoAlertViewModel.actionText)
        } else {
            infoAlertView.hide()
        }
    }
    
    private func initFloatingPanel() {
        floatingPanel = FloatingPanelController()
        floatingPanel.setup()
        floatingPanel.delegate = self
        floatingPanel.addPanel(toParent: self)
        floatingPanel.show(animated: true)
    }
    
    private func destoryFloatingPanel() {
        floatingPanel.removePanelFromParent(animated: false)
    }
    
    private func startServersUpdate() {
        updateServersList()
        updateServersTimer = Timer.scheduledTimer(timeInterval: 60 * 15, target: self, selector: #selector(updateServersList), userInfo: nil, repeats: true)
    }
    
    private func startPingService(updateServerListDidComplete: Bool) {
        if updateServerListDidComplete {
            DispatchQueue.delay(0.5) {
                Pinger.shared.ping()
            }
        }
    }
    
}
