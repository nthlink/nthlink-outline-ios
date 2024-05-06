import UIKit
import NetworkExtension

let appGroup = "group.com.outline.sdk"
let config_server_key = "CONFIG_SERVER"
let config_encrypt_key = "CONFIG_ENCRYPT"
let config_password_key = "CONFIG_PASSWORD"

class HomeController: UITableViewController {
    
    public var vpnManager = NEVPNManager.shared()
        
    @IBOutlet weak var vpnToggleBtn: UIButton!
        
    @IBAction func toggleVpn(_ sender: Any) {
        self.vpnManager.isEnabled = true
        self.vpnManager.saveToPreferences { error in
            guard error == nil else {
                print("Unable to save VPN configuration: \(String(describing: error))")
                return
            }
            self.vpnManager.loadFromPreferences { error in
                guard error == nil else {
                    print("Unable to load VPN configuration: \(String(describing: error))")
                    return
                }

                NotificationCenter.default.addObserver(self, selector: #selector(self.updateVpnStatus), name: NSNotification.Name.NEVPNStatusDidChange, object: self.vpnManager.connection)

                switch self.vpnManager.connection.status {
                case .disconnected, .invalid:
                    do {
                        UserDefaults.init(suiteName: appGroup)?.set("159.203.107.7:443", forKey: config_server_key)
                        UserDefaults.init(suiteName: appGroup)?.set("chacha20-ietf-poly1305", forKey: config_encrypt_key)
                        UserDefaults.init(suiteName: appGroup)?.set("r6WCeI6GwYrEQDAq7aEvxQ", forKey: config_password_key)
                        try self.vpnManager.connection.startVPNTunnel()
                    } catch {
                        print("Unable to start VPN tunnel: \(error)")
                    }
                default:
                    self.vpnManager.connection.stopVPNTunnel()
                }
            }
        }
    }
    
    func loadOrCreateVPNManager(completionHandler: @escaping (Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences(completionHandler: { managers, error in
            guard let managers = managers, error == nil else {
                completionHandler(error)
                return
            }
            // Take an existing VPN configuration or create a new one if none exist.
            if managers.count > 0 {
                self.vpnManager = managers[0]
            } else {
                let manager = NETunnelProviderManager()
                manager.protocolConfiguration = NETunnelProviderProtocol()
                manager.localizedDescription = "VPN"
                manager.protocolConfiguration?.serverAddress = "VPN"
                manager.saveToPreferences { error in
                    guard error == nil else {
                        completionHandler(error)
                        return
                    }
                    manager.loadFromPreferences { error in
                        self.vpnManager = manager
                    }
                }
            }
            completionHandler(nil)
        })
    }

    @objc func updateVpnStatus() {
        // Update button label according to VPN connection status.
        switch vpnManager.connection.status {
        case .connected:
            vpnToggleBtn.setTitle("Connected", for: .normal)
            break
        case .connecting:
            vpnToggleBtn.setTitle("Connecting", for: .normal)
            break
        case .disconnected:
            vpnToggleBtn.setTitle("Disconnected", for: .normal)
            break
        case .disconnecting:
            vpnToggleBtn.setTitle("Disconnecting", for: .normal)
            break
        case .invalid:
            vpnToggleBtn.setTitle("Invalid", for: .normal)
            break
        case .reasserting:
            vpnToggleBtn.setTitle("Reasserting", for: .normal)
            break
        default:
            vpnToggleBtn.setTitle("Unknown", for: .normal)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.updateVpnStatus()
        
        // Load or create a VPN configuration, this will ask user for VPN permission for the first time.
        loadOrCreateVPNManager(completionHandler: { error in
            guard error == nil else {
                print("Unable to load or create VPN manager: \(String(describing: error))")
                return
            }
            self.updateVpnStatus()
            // Observe VPN connection status changes.
            NotificationCenter.default.addObserver(self, selector: #selector(self.updateVpnStatus), name: NSNotification.Name.NEVPNStatusDidChange, object: self.vpnManager.connection)
        })
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NEVPNStatusDidChange, object: self.vpnManager.connection)
    }
}
