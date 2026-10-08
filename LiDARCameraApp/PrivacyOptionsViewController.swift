import UIKit

final class PrivacyOptionsViewController: UITableViewController {
    private let sharingSwitch = UISwitch()

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Privacy"
        sharingSwitch.isOn = AIPrivacy.hasConsent
        sharingSwitch.accessibilityLabel = "AI photo sharing"
        sharingSwitch.addTarget(self, action: #selector(sharingChanged), for: .valueChanged)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        if indexPath.row == 0 {
            cell.textLabel?.text = "AI photo sharing"
            cell.accessoryView = sharingSwitch
            cell.selectionStyle = .none
        } else {
            cell.textLabel?.text = "Privacy Policy"
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityTraits.insert(.button)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Photos are shared only when you request an AI description. Camera and LiDAR feedback stay on your device."
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 1 { navigationController?.pushViewController(PrivacyPolicyViewController(), animated: true) }
    }

    @objc private func sharingChanged() {
        guard sharingSwitch.isOn else {
            AIPrivacy.revokeConsent()
            return
        }
        // Enabling permission never captures or uploads a photo by itself.
        sharingSwitch.setOn(false, animated: true)
        let alert = UIAlertController(title: "Allow AI Photo Sharing?", message: AIPrivacy.sharingExplanation, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Allow", style: .default) { [weak self] _ in
            AIPrivacy.grantConsent()
            self?.sharingSwitch.setOn(true, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        present(alert, animated: true)
    }
}

final class PrivacyNavigationController: UINavigationController, UIAdaptivePresentationControllerDelegate {
    var onClose: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers.first?.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
    }

    @objc func close() { dismiss(animated: true, completion: onClose) }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { onClose?() }
}
