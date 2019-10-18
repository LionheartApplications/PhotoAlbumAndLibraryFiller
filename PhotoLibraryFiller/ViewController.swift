/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main ViewController that configures the UI, listens for user actions and inputs, and then configures the photo library filler class.
*/

import UIKit

class ViewController: UIViewController, PhotoLibraryFillerDelegate, UITextFieldDelegate {
    
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var numberTextField: UITextField!
    @IBOutlet weak var actionButton: UIButton!
    
    private let photoLibraryFiller = PhotoLibraryFiller()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        centerView.layer.cornerRadius = 25
        photoLibraryFiller.delegate = self
        updateActionButton()
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: - Update Methods
    
    private func updateActionButton() {
        let title = photoLibraryFiller.active ? "Stop" : "Add Photos"
        
        UIView.performWithoutAnimation {
            actionButton.setTitle(title, for: .normal)
            actionButton.layoutIfNeeded()
        }
    }
    
    private func updatePhotoLibraryFiller() {
        if !photoLibraryFiller.active {
            photoLibraryFiller.photosToAdd = Int(numberTextField.text!) ?? 0
        }
    }
    
    private func updateTextField() {
        numberTextField.isEnabled = !photoLibraryFiller.active
        if photoLibraryFiller.active {
            numberTextField.text = "\(photoLibraryFiller.photosToAdd)"
        }
    }
    
    private func animateAddedImage(image: UIImage) {
        let view = self.view!
        if view.subviews.count > 75 {
            // Skip creating an animating view if we already have enough of them. In case photos are generated too fast for the UI to keep up.
            return
        }
        
        let aspectRatio = image.size.width / image.size.height
        let imageView = UIImageView(image: image)
        let height = CGFloat(50.0)
        let width = height * aspectRatio
        let viewCenter = centerView.center
        imageView.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        imageView.center = viewCenter
        view.insertSubview(imageView, at: 0)
        
        let finalScale = CGFloat(5)
        let distance = max(view.bounds.size.width, view.bounds.size.height) + width * finalScale
        UIView.animate(withDuration: 1.0, delay: 0, options: .curveEaseIn, animations: {
            let direction = self.randomFloat() * CGFloat.pi * 2
            imageView.center = CGPoint(x: viewCenter.x + distance * cos(direction),
                                       y: viewCenter.y + distance * sin(direction))
            let rotationTransform = CGAffineTransform(rotationAngle: self.randomFloat() * CGFloat.pi * 2)
            let scaleTransform = CGAffineTransform(scaleX: finalScale, y: finalScale)
            imageView.transform = rotationTransform.concatenating(scaleTransform)
        }, completion: { _ in
            imageView.removeFromSuperview()
        })
    }

    private func randomFloat() -> CGFloat {
        return CGFloat(CGFloat(arc4random()) / CGFloat(UINT32_MAX))
    }
    
    // MARK: - IBActions
    
    @IBAction func actionButtonTapped(_ sender: Any) {
        updatePhotoLibraryFiller()
        photoLibraryFiller.active = !photoLibraryFiller.active
    }
    
    @IBAction func textFieldEditingChanged(_ sender: Any) {
        updatePhotoLibraryFiller()
    }
    
    // MARK: - PhotoLibraryFillerDelegate
    
    func photoLibraryFillerDidUpdate(_ photoLibraryFiller: PhotoLibraryFiller) {
        UIApplication.shared.isIdleTimerDisabled = photoLibraryFiller.active
        
        updateTextField()
        updateActionButton()
    }
    
    func photoLibraryFiller(_ photoLibraryFiller: PhotoLibraryFiller, didGenerate image: UIImage) {
        animateAddedImage(image: image)
    }
    
    func photoLibraryFiller(_ photoLibraryFiller: PhotoLibraryFiller, didEncounterErrorWith message: String) {
        guard presentedViewController == nil else { return }
        
        let alertController = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Ok", style: .default, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        }))
        present(alertController, animated: true, completion: nil)
    }
    
    // MARK: - UITextFieldDelegate
    
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    public func textFieldDidEndEditing(_ textField: UITextField) {
        updatePhotoLibraryFiller()
        updateActionButton()
    }
}
