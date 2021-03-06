//
//  ViewController.swift
//  CoreML in ARKit
//
//  Created by Hanley Weng on 14/7/17.
//  Copyright © 2017 CompanyName. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision
import Photos

class ARViewController: UIViewController, ARSCNViewDelegate, UIGestureRecognizerDelegate {
    
    var active = false
    var breed = ""
    var panGesture = UIPanGestureRecognizer()
    
    let showListBtn = UIButton()
    let nearYouView = UIView()
    let nearYouLbl = UILabel()
    let nearYouImg = UIImageView()
    
    @IBOutlet weak var foundBreedView: FoundBreedView!
    
    // SCENE
    @IBOutlet var sceneView: ARSCNView!
    let bubbleDepth : Float = 0.01 // the 'depth' of 3D text
    var latestPrediction : String = "…" // a variable containing the latest CoreML prediction
    
    // COREML
    var visionRequests = [VNRequest]()
    let dispatchQueueML = DispatchQueue(label: "com.hw.dispatchqueueml") // A Serial Queue
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = false
        
        // Create a new scene
        let scene = SCNScene()
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // Enable Default Lighting - makes the 3D text a bit seguepoppier.
        sceneView.autoenablesDefaultLighting = true
        
        //////////////////////////////////////////////////
        // Tap Gesture Recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tapGesture)
        
        //////////////////////////////////////////////////
        
        // Set up Vision Model
        guard let selectedModel = try? VNCoreMLModel(for: dogBreed().model) else { // (Optional) This can be replaced with other models on https://developer.apple.com/machine-learning/
            fatalError("Could not load model. Ensure model has been drag and dropped (copied) to XCode Project from https://developer.apple.com/machine-learning/ . Also ensure the model is part of a target (see: https://stackoverflow.com/questions/45884085/model-is-not-part-of-any-target-add-the-model-to-a-target-to-enable-generation ")
        }
        
        // Set up Vision-CoreML Request
        let classificationRequest = VNCoreMLRequest(model: selectedModel, completionHandler: classificationCompleteHandler)
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop // Crop from centre of images and scale to appropriate size.
        visionRequests = [classificationRequest]
        
        // Begin Loop to Update CoreML
        loopCoreMLUpdate()
        
        let gestureUp = UISwipeGestureRecognizer(target: self, action: #selector(gestureSegue))
        gestureUp.direction = .up
        sceneView.addGestureRecognizer(gestureUp)
        
        let tapped = UITapGestureRecognizer(target: self, action: #selector(gestureSegue))
        tapped.numberOfTapsRequired = 1
        nearYouView.addGestureRecognizer(tapped)
        
        nearYouView.frame = CGRect(x: 0.0, y: sceneView.frame.size.height, width: sceneView.frame.size.width, height: 80.0)
        nearYouView.backgroundColor = UIColor(red: 248/255, green: 161/255, blue: 62/255, alpha: 1.0)
        nearYouView.roundCorners(corners: [.topLeft, .topRight], radius: 25)
        sceneView.addSubview(nearYouView)
        
        showListBtn.frame = CGRect(x: nearYouView.frame.size.width - 80, y: (nearYouView.frame.size.height / 2) - 30, width: 60.0, height: 60.0)
        showListBtn.addTarget(self, action: #selector(gestureSegue), for: .touchUpInside)
        nearYouView.addSubview(showListBtn)
        
        nearYouLbl.font = UIFont(name: "Avenir-Heavy", size: 22.0)
        nearYouLbl.text = "Dogs Near You"
        nearYouLbl.textAlignment = .left
        nearYouLbl.textColor = UIColor.white
        nearYouLbl.frame = CGRect(x: 20, y: (nearYouView.frame.size.height / 2) - 12, width: nearYouView.frame.size.width - 50, height: 24.0)
        
        nearYouView.addSubview(nearYouLbl)
        
        foundBreedView.roundCorners(corners: .allCorners, radius: 25)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        // Enable plane detection
        configuration.planeDetection = .horizontal
        
        // Run the view's session
        sceneView.session.run(configuration)
        if active == true {
            toggleNearYouView()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        sceneView.scene.rootNode.removeFromParentNode()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            // Do any desired updates to SceneKit here.
        }
    }
    
    // MARK: - Status Bar: Hide
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    // MARK: - Interaction
    
    @objc func handleTap(gestureRecognize: UITapGestureRecognizer) {
        // HIT TEST : REAL WORLD
        // Get Screen Centre
        let screenCentre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
        
        let arHitTestResults : [ARHitTestResult] = sceneView.hitTest(screenCentre, types: [.featurePoint]) // Alternatively, we could use '.existingPlaneUsingExtent' for more grounded hit-test-points.
        
        if let closestResult = arHitTestResults.first {
            // Get Coordinates of HitTest
            let transform : matrix_float4x4 = closestResult.worldTransform
            let worldCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            
            // Create 3D Text
            let node : SCNNode = createNewBubbleParentNode(latestPrediction)
            sceneView.scene.rootNode.addChildNode(node)
            node.position = worldCoord
            foundBreedView.breedLabel?.text = latestPrediction
            nearYouLbl.text = "\(latestPrediction)'s for you to adopt"
            if active == false {
                toggleNearYouView()
            }
        }
    }
    
    func toggleNearYouView() {
        if active == false {
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: {
                self.nearYouView.frame.origin.y -= 80
            }, completion: { (_) in
                self.active = true
            })
        }
        else {
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: {
                self.nearYouView.frame.origin.y += 80
            }, completion: { (_) in
                self.active = false
            })
        }
    }
    
    func createNewBubbleParentNode(_ text : String) -> SCNNode {
        // Warning: Creating 3D Text is susceptible to crashing. To reduce chances of crashing; reduce number of polygons, letters, smoothness, etc.
        
        // TEXT BILLBOARD CONSTRAINT
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        
        
        let screenCentre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
        
        let arHitTestResults : [ARHitTestResult] = sceneView.hitTest(screenCentre, types: [.featurePoint]) // Alternatively, we could use '.existingPlaneUsingExtent' for more grounded hit-test-points.
        
        if let closestResult = arHitTestResults.first {
            // Get Coordinates of HitTest
            let transform : matrix_float4x4 = closestResult.worldTransform
            //sceneView.session.add(anchor: ARAnchor(transform: transform))
            let worldCoord = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            
            
            let textNode = SCNNode()
            textNode.scale = SCNVector3(x: 0.1, y: 0.1, z: 0.1)
            textNode.opacity = 0.0
            self.sceneView.scene.rootNode.addChildNode(textNode)
            textNode.position = worldCoord
            let backNode = SCNNode()
            let plaque = SCNBox(width: 0.075, height: 0.03, length: 0.01, chamferRadius: 0.005)
            plaque.firstMaterial?.diffuse.contents = UIColor(white: 1.0, alpha: 0.6)
            backNode.geometry = plaque
            backNode.position.y += 0.09
            
            //Set up card view
            let imageView = UIView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
            imageView.backgroundColor = .clear
            imageView.alpha = 1.0
            let titleLabel = UILabel(frame: CGRect(x: 0, y: 150, width: imageView.frame.width + 20, height: 100))
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 1
            titleLabel.font = UIFont(name: "Avenir-Heavy", size: 84)
            titleLabel.text = text
            titleLabel.backgroundColor = .clear
            imageView.addSubview(titleLabel)
            
            let texture = UIImage.imageWithView(view: imageView)
            
            let infoNode = SCNNode()
            let infoGeometry = SCNPlane(width: 0.13, height: 0.09)
            infoGeometry.firstMaterial?.diffuse.contents = texture
            infoNode.geometry = infoGeometry
            infoNode.position.y += 0.09
            infoNode.position.z += 0.0055
            
            textNode.addChildNode(backNode)
            textNode.addChildNode(infoNode)
            
            textNode.constraints = [billboardConstraint]
            textNode.runAction(SCNAction.scale(to: 0.0, duration: 0))
            backNode.runAction(SCNAction.scale(to: 0.0, duration: 0))
            infoNode.runAction(SCNAction.scale(to: 0.0, duration: 0))
            textNode.runAction(SCNAction.fadeOpacity(to: 0.0, duration: 0))
            backNode.runAction(SCNAction.fadeOpacity(to: 0.0, duration: 0))
            infoNode.runAction(SCNAction.fadeOpacity(to: 0.0, duration: 0))
            
            textNode.runAction(SCNAction.wait(duration: 0.01))
            backNode.runAction(SCNAction.wait(duration: 0.01))
            infoNode.runAction(SCNAction.wait(duration: 0.01))
            textNode.runAction(SCNAction.scale(to: 1.0, duration: 0.3) )
            backNode.runAction(SCNAction.scale(to: 1.0, duration: 0.3) )
            infoNode.runAction(SCNAction.scale(to: 1.0, duration: 0.3) )
            textNode.runAction(SCNAction.fadeOpacity(to: 1.0, duration: 0.3))
            backNode.runAction(SCNAction.fadeOpacity(to: 1.0, duration: 0.3))
            infoNode.runAction(SCNAction.fadeOpacity(to: 1.0, duration: 0.3))
            
            return textNode
        }
        else {
            return SCNNode()
        }
        
    }
    
    // MARK: - CoreML Vision Handling
    
    func loopCoreMLUpdate() {
        // Continuously run CoreML whenever it's ready. (Preventing 'hiccups' in Frame Rate)
        dispatchQueueML.async {
            // 1. Run Update.
            self.updateCoreML()
            
            // 2. Loop this function.
            self.loopCoreMLUpdate()
        }
        
    }
    
    func classificationCompleteHandler(request: VNRequest, error: Error?) {
        // Catch Errors
        if error != nil {
            print("Error: " + (error?.localizedDescription)!)
            return
        }
        guard let observations = request.results else {
            print("No results")
            return
        }
        
        // Get Classifications
        let classifications = observations[0...0] // top 2 results
            .flatMap({ $0 as? VNClassificationObservation })
            .map({ "\($0.identifier) \(String(format:"- %.2f", $0.confidence))" })
            .joined(separator: "\n")
        
        
        
        DispatchQueue.main.async {
            // Print Classifications
            //print(classifications)
            //print("--")
            
            // Store the latest prediction
            var objectName:String = "…"
            var confidence:String = "…"
            objectName = classifications.components(separatedBy: "-")[0]
            objectName = objectName.components(separatedBy: " ")[0]
            confidence = classifications.components(separatedBy: "-")[1]
            confidence = confidence.trimmingCharacters(in: .whitespaces)
            self.latestPrediction = objectName
            self.breed = objectName
            print(confidence)
            
            if let double = Double(confidence) {
                if double >= 0.75 {
                    self.foundBreedView.breedLabel?.text = "Doge!! Tap the reticle now"
                }
                else if double >= 0.5{
                    self.foundBreedView.breedLabel?.text = "maybe 🐕?"
                }
                else {
                    self.foundBreedView.breedLabel?.text = "Barky can identify other puppers!"
                }
            }
            else {
                self.foundBreedView.breedLabel?.text = "Barky can identify other puppers!"
            }
        }
    }
    
    func updateCoreML() {
        ///////////////////////////
        // Get Camera Image as RGB
        let pixbuff : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        if pixbuff == nil { return }
        let ciImage = CIImage(cvPixelBuffer: pixbuff!)
        // Note: Not entirely sure if the ciImage is being interpreted as RGB, but for now it works with the Inception model.
        // Note2: Also uncertain if the pixelBuffer should be rotated before handing off to Vision (VNImageRequestHandler) - regardless, for now, it still works well with the Inception model.
        
        ///////////////////////////
        // Prepare CoreML/Vision Request
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        // let imageRequestHandler = VNImageRequestHandler(cgImage: cgImage!, orientation: myOrientation, options: [:]) // Alternatively; we can convert the above to an RGB CGImage and use that. Also UIInterfaceOrientation can inform orientation values.
        
        ///////////////////////////
        // Run Image Request
        do {
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
        
    }
    
    @objc func gestureSegue() {
        self.performSegue(withIdentifier: "toBreed", sender: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "toBreed" {
            let breedViewController = segue.destination as! BreedViewController
            breedViewController.breed = breed
        }
    }
}

extension UIImage {
    class func imageWithView(view: UIView) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(view.bounds.size, false, 0.0)
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img!
    }
}

extension UIFont {
    // Based on: https://stackoverflow.com/questions/4713236/how-do-i-set-bold-and-italic-on-uilabel-of-iphone-ipad
    func withTraits(traits:UIFontDescriptorSymbolicTraits...) -> UIFont {
        let descriptor = self.fontDescriptor.withSymbolicTraits(UIFontDescriptorSymbolicTraits(traits))
        return UIFont(descriptor: descriptor!, size: 0)
    }
}
