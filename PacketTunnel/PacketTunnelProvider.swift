import NetworkExtension
import Outline

let appGroup = "group.com.outline.sdk"
let config_server_key = "CONFIG_SERVER"
let config_encrypt_key = "CONFIG_ENCRYPT"
let config_password_key = "CONFIG_PASSWORD"

public let tunWriteQueue = DispatchQueue(label: "nthlink.tun.write", qos: .userInteractive)
public let tunReadQueue = DispatchQueue(label: "nthlink.tun.read", qos: .userInteractive)

public enum TunnelError: Error {
    case notFound
}

// Peak the IP version of an IP packet.
public func peekIPVersion(_ data: Data) -> UInt8? {
    guard data.count >= 20 else {
        return nil
    }
    let version = (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count).pointee >> 4
    return version
}

// Extending the OutlinePacketWriterProtocol in order to write back IP packets.
extension PacketTunnelProvider: OutlinePacketWriterProtocol {
    public func writePacket(_ packet: Data?) {
        guard let packet = packet else {
            NSLog("Unexpected NULL IP packet")
            return
        }
        tunWriteQueue.async {
            if let version = peekIPVersion(packet) {
                switch version {
                case 4:
                    self.packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET)])
                    break
                case 6:
                    self.packetFlow.writePackets([packet], withProtocols: [NSNumber(value: AF_INET6)])
                    break
                default:
                    break
                }
            }
        }
    }
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "240.0.0.1")
        settings.ipv4Settings = NEIPv4Settings(addresses: ["240.0.0.2"], subnetMasks: ["255.255.255.0"])
        settings.ipv4Settings?.includedRoutes = [NEIPv4Route.`default`()]
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1"])
        settings.mtu = 1500
        setTunnelNetworkSettings(settings) { error in
            guard error == nil else {
                NSLog("Setup tunnel failed: \(String(describing: error))")
                completionHandler(error)
                return
            }
            
            let ssPrefix = "Prefix112233"
            // self implements OutlinePacketWriterProtocol which will be used by outline to write back IP packets.
            var outlineError: NSError?
            if let ssServerAddress = UserDefaults.init(suiteName: appGroup)?.string(forKey: config_server_key) {
                let ssCipher = UserDefaults.init(suiteName: appGroup)?.string(forKey: config_encrypt_key)
                let ssPassword = UserDefaults.init(suiteName: appGroup)?.string(forKey: config_password_key)
                
                let outlineRet = OutlineStart(self, nil, ssServerAddress, ssCipher, ssPassword, ssPrefix, &outlineError)
                if (!outlineRet) {
                    if let err = outlineError {
                        NSLog("Start outline failed: \(err.localizedDescription)")
                        completionHandler(err)
                        return
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                    self.handlePackets()
                })
                NSLog("VPN tunnel started.")
                completionHandler(nil)
            } else {
                NSLog("Config not found")
                completionHandler(TunnelError.notFound)
            }
            
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        var outlineError: NSError?
        let outlineRet = OutlineStop(&outlineError)
        if (!outlineRet) {
            if let err = outlineError {
                NSLog("Stop outline failed: \(err.localizedDescription)")
            }
        }
        NSLog("VPN tunnel stopped.")
        completionHandler()
    }
    
    // Continuously read IP packets from TUN and input to outline.
    func handlePackets() {
        packetFlow.readPackets() { packets, _ in
            for packet in packets {
                tunReadQueue.async {
                    OutlineWritePacket(packet)
                }
            }
            self.handlePackets()
        }
    }
}
