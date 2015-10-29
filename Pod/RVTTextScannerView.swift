//
//  RVTTextScannerView.swift
//
//  Created by Adam Share on 9/30/15.
//  Copyright (c) 2015. All rights reserved.
//

import Foundation
import UIKit
import TesseractOCR
import GPUImage
import PureLayout

protocol RVTTextScannerViewDelegate: class {
    
    func scannerDidRecognizeText(scanner: RVTTextScannerView, textResult: RVTTextResult, image: UIImage?)
    func scannerDidFindCommontextResult(scanner: RVTTextScannerView, textResult: RVTTextResult, image: UIImage?)
    func scannerDidStopScanning(scanner: RVTTextScannerView)
    func scannerOptimizationHint(scanner: RVTTextScannerView, hint: String!)
}

extension RVTTextScannerViewDelegate {
    
    func scannerDidStopScanning(scanner: RVTTextScannerView) {
        
    }
    
    func scannerDidFindCommontextResult(scanner: RVTTextScannerView, textResult: RVTTextResult, image: UIImage?) {
        
    }
    
    func scannerOptimizationHint(scanner: RVTTextScannerView, hint: String!) {
        
    }
}

public class RVTTextScannerView: UIView, G8TesseractDelegate {
    
    public class func scanImage(var image: UIImage) -> RVTTextResult? {
        
        let tesseract:G8Tesseract = G8Tesseract(language: "eng")
        image = image.g8_blackAndWhite()
        tesseract.image = image
        tesseract.recognize()
        let result = tesseract.recognizedText
        G8Tesseract.clearCache()
        
        if let text = result {
            return RVTTextResult(withText: text)
        }
        
        return nil
    }
    
    var showCropView: Bool! = false {
        didSet {
            self.cropView?.removeFromSuperview()
            if self.showCropView == true {
                self.cropView = RVTScanCropView.addToScannerView(self)
                self.cropRect = self.cropView!.cropRect
            }
            else {
                self.cropRect = self.bounds
            }
        }
    }
    
    var allowsHorizontalScanning = false
    var cropView: RVTScanCropView?
    var gpuImageView: GPUImageView!
    
    weak var delegate: RVTTextScannerViewDelegate?
    
    var timer: NSTimer?
    
    /// For capturing the video and passing it on to the filters.
    private let videoCamera: GPUImageVideoCamera = GPUImageVideoCamera(sessionPreset: AVCaptureSessionPreset1920x1080, cameraPosition: .Back)
    
    let ocrOperationQueue = NSOperationQueue()
    
    // Quick reference to the used filter configurations
    var exposure = GPUImageExposureFilter()
    var highlightShadow = GPUImageHighlightShadowFilter()
    var saturation = GPUImageSaturationFilter()
    var contrast = GPUImageContrastFilter()
    var crop = GPUImageCropFilter()
    
    var cropRect: CGRect = UIScreen.mainScreen().bounds {
        didSet {
            self.foundTextResults = [:]
        }
    }
    
    var matchThreshold = 3
    var foundTextResults: [String: RVTTextResult] = [:]
    
    var tesseract:G8Tesseract = G8Tesseract(language: "eng")
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
     
        self.setup()
    }
    
    public override func awakeFromNib() {
        super.awakeFromNib()
        
        self.setup()
    }
    
    func setup() {
        
        videoCamera.outputImageOrientation = .Portrait;
        self.gpuImageView = GPUImageView(frame: self.frame)
        self.addSubview(gpuImageView)
        self.gpuImageView.autoCenterInSuperview()
        self.gpuImageView.autoPinEdgeToSuperviewEdge(.Left)
        self.gpuImageView.autoPinEdgeToSuperviewEdge(.Right)
        self.gpuImageView.autoMatchDimension(.Height, toDimension: .Width, ofView: self.gpuImageView, withMultiplier: 16/9)
        
        self.ocrOperationQueue.maxConcurrentOperationCount = 1
        
        // Filter settings
        highlightShadow.highlights = 0
        
        // Chaining the filters
        videoCamera.addTarget(exposure)
        exposure.addTarget(highlightShadow)
        highlightShadow.addTarget(saturation)
        saturation.addTarget(contrast)
        contrast.addTarget(self.gpuImageView)
        
        self.tesseract.delegate = self
    }
    
    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        if self.superview == nil {
            UIDevice.currentDevice().endGeneratingDeviceOrientationNotifications()
        }
        else {
            UIDevice.currentDevice().beginGeneratingDeviceOrientationNotifications()
        }
    }
    
    /**
     Starts a scan immediately
     */
    public func startScan() {
        
        self.videoCamera.startCameraCapture()
        
        self.timer?.invalidate()
        self.timer = nil;
        self.timer = NSTimer.scheduledTimerWithTimeInterval(0.05, target: self, selector: Selector("scan"), userInfo: nil, repeats: false)
    }
    
    /**
     Stops a scan
     */
    public func stopScan() {
        
        self.videoCamera.stopCameraCapture()
        timer?.invalidate()
        timer = nil
        self.delegate?.scannerDidStopScanning(self)
    }
    
    /**
     Perform a scan
     */
    public func scan() {
        
        NSOperationQueue.mainQueue().addOperationWithBlock({ () -> Void in
            
            self.timer?.invalidate()
            self.timer = nil
            
            let startTime = NSDate()
            
            let currentFilterConfiguration = self.contrast
            currentFilterConfiguration.useNextFrameForImageCapture()
            currentFilterConfiguration.framebufferForOutput()?.disableReferenceCounting()
            let snapshot = currentFilterConfiguration.imageFromCurrentFramebuffer()
            
            if snapshot == nil {
                self.startScan()
                return
            }
            
            
            self.ocrOperationQueue.addOperationWithBlock({[weak self] () -> Void in
                
                guard let weakSelf = self else {
                    return
                }
                
                var result:String?
                var image: UIImage?
                var component: RVTTextResult?
                var existingComponent: RVTTextResult?
                
                // Crop scan area
                
                var cropRect:CGRect! = weakSelf.cropRect
                cropRect.origin.y -= weakSelf.gpuImageView.frame.origin.y
                
                let fullImage = UIImage(CGImage: snapshot.CGImage!)
                
                let frameHeight = weakSelf.gpuImageView.frame.size.height;
                let snapShotHeight = fullImage.size.height;
                let ratio = snapShotHeight/frameHeight
                cropRect.origin.x *= ratio;
                cropRect.origin.y *= ratio;
                cropRect.size.width *= ratio;
                cropRect.size.height *= ratio;
                
                
                let imageRef:CGImageRef! = CGImageCreateWithImageInRect(snapshot.CGImage, cropRect);
                image =   UIImage(CGImage: imageRef)
                
                if weakSelf.allowsHorizontalScanning {
                    
                    var rotate = false
                    let selectedFilter = GPUImageTransformFilter()
                    
                    let orientation = UIDevice.currentDevice().orientation
                    
                    switch orientation {
                    case .LandscapeLeft:
                        selectedFilter.setInputRotation(kGPUImageRotateLeft, atIndex: 0)
                        rotate = true
                        break
                    case .LandscapeRight:
                        selectedFilter.setInputRotation(kGPUImageRotateRight, atIndex: 0)
                        rotate = true
                        break
                    case .Portrait:
                        break
                    default:
                        break
                    }
                    
                    if rotate {
                        image = selectedFilter.imageByFilteringImage(image)
                    }
                }
                
                image = image?.g8_blackAndWhite()
                weakSelf.tesseract.image = image
                weakSelf.tesseract.recognize()
                result = weakSelf.tesseract.recognizedText
                G8Tesseract.clearCache()
                weakSelf.cropView?.progress = 0
                
                if let text = result {
                    component = RVTTextResult(withText: text)
                    existingComponent = weakSelf.matchedPastComponentThreshold(component!)
                }
                
                NSOperationQueue.mainQueue().addOperationWithBlock({ () -> Void in
                    
                    var hint = ""
                    if result?.characters.count == 0 {
                        weakSelf.cropView?.progressView.hidden = true
                        hint = "Align text to top left corner"
                    }
                    else {
                        if (abs(startTime.timeIntervalSinceNow) > 1.5 && self?.cropView?.frame.size.height > 100) {
                            hint = "Hint: Resize the scanner to fit only the required text for faster results"
                        }
                    }
                    
                    weakSelf.cropView?.hintLabel.text = hint
                    if hint.characters.count > 0 {
                        self?.delegate?.scannerOptimizationHint(weakSelf, hint: hint)
                    }
                    
                    if component != nil {
                        weakSelf.delegate?.scannerDidRecognizeText(weakSelf, textResult: component!, image: image);
                    }
                    
                    if existingComponent != nil {
                        weakSelf.delegate?.scannerDidFindCommontextResult(weakSelf, textResult: existingComponent!, image: image)
                    }
                    
                    self?.startScan()
                })
                })
        })
    }
    
    func matchedPastComponentThreshold(textResult: RVTTextResult) -> RVTTextResult? {
        
        if textResult.text.characters.count == 0 {
            return nil
        }
        
        if textResult.key.characters.count <= 2 {
            return nil
        }
        
        if let pasttextResult = self.foundTextResults[textResult.key] {
            pasttextResult.matched++
            
            if pasttextResult.matched >= self.matchThreshold {
                self.foundTextResults = [:]
                return pasttextResult
            }
            
            return nil
        }
        
        self.foundTextResults[textResult.key] = textResult
        return nil
    }
    
    
    public func progressImageRecognitionForTesseract(tesseract: G8Tesseract!) {
        
        self.cropView?.progress = tesseract.progress
    }
    
    var cancelCurrentScan: Bool = false
    
    public func shouldCancelImageRecognitionForTesseract(tesseract: G8Tesseract!) -> Bool {
        
        if cancelCurrentScan {
            cancelCurrentScan = false
            return true
        }
        
        return cancelCurrentScan
    }
}


public class RVTTextResult {
    
    init (withText text: String) {
        self.text = text
    }
    
    var matched: Int = 0
    var text: String!
    
    var lines: [String] {
        var lines = self.text.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())
        
        lines = lines.filter({ $0.characters.count != 0 })
        
        return lines
    }
    
    var key: String {
        
        if let firstText = self.lines.first {
            let squashed = firstText.stringByReplacingOccurrencesOfString("[ ]+", withString: "", options: NSStringCompareOptions.RegularExpressionSearch, range: firstText.startIndex..<firstText.endIndex)
            let final = squashed.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
            return final.lowercaseString
        }
        
        return ""
    }
    
    var whiteSpacedComponents: [String] {
        
        let squashed = self.text.stringByReplacingOccurrencesOfString("\n", withString: " ").stringByReplacingOccurrencesOfString("[ ]+", withString: " ", options: NSStringCompareOptions.RegularExpressionSearch, range: text.startIndex..<text.endIndex)
        let final = squashed.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        
        return final.componentsSeparatedByString(" ")
    }
    
}



class RVTScanCropView: UIView {
    
    var showProgressView: Bool! = true {
        didSet {
            self.progressView.hidden = !self.showProgressView
        }
    }
    
    var showHintLabel: Bool! = true {
        didSet {
            self.hintLabel.hidden = !self.showHintLabel
        }
    }
    
    var progress: UInt! = 0 {
        didSet {
            NSOperationQueue.mainQueue().addOperationWithBlock { () -> Void in
                
                if self.progress == 0 || self.progress == 100 {
                    self.progressView.hidden = true
                }
                else {
                    self.progressView.hidden = false
                    self.progressLeftLayoutConstraint.constant = CGFloat(self.progress)/100 * self.cropRect.width
                    self.layoutIfNeeded()
                }
            }
        }
    }
    
    var edgeColor: UIColor! = UIColor.lightGrayColor() {
        didSet {
            self.cornerShapeLayer.strokeColor = self.edgeColor.CGColor;
            self.resizedView.layer.borderColor = self.edgeColor.colorWithAlphaComponent(0.3).CGColor
        }
    }
    
    var progressColor: UIColor! = UIColor.lightGrayColor() {
        didSet {
            self.progressView.backgroundColor = self.progressColor.colorWithAlphaComponent(0.5)
        }
    }
    
    var cornerShapeLayer = CAShapeLayer()
    
    var cropRect: CGRect {
        
        return self.resizedView.frame
    }
    
    var progressView: UIView!
    var resizedView: UIView!
    var hintLabel: UILabel!
    
    var progressLeftLayoutConstraint: NSLayoutConstraint!
    
    var topConstraint: NSLayoutConstraint!
    var leftConstraint: NSLayoutConstraint!
    var bottomConstraint: NSLayoutConstraint!
    var rightConstraint: NSLayoutConstraint!
    
    class func addToScannerView(scannerView: RVTTextScannerView) -> RVTScanCropView {
        
        let containerView = RVTScanCropView(frame: scannerView.bounds)
        scannerView.addSubview(containerView)
        containerView.autoPinEdgesToSuperviewEdges()
        
        return containerView
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.setupViews()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        self.setupViews()
    }
    
    func setupViews() {
        
        self.backgroundColor = UIColor.clearColor()
        
        let cropView = UIView()
        self.resizedView = cropView
        self.addSubview(cropView)
        
        cropView.layer.borderColor = self.edgeColor.colorWithAlphaComponent(0.5).CGColor
        cropView.layer.borderWidth = 1.0
        cropView.backgroundColor = UIColor.clearColor()
        
        let cropConstraints = cropView.autoPinEdgesToSuperviewEdgesWithInsets(UIEdgeInsetsMake(self.frame.size.height/3, 16, self.frame.size.height/3, 16))
        
        for layoutConstraint in cropConstraints {
            
            switch layoutConstraint.firstAttribute {
            case .Leading, .LeadingMargin, .Left, .LeftMargin:
                self.leftConstraint = layoutConstraint
                break
            case .TopMargin, .Top:
                self.topConstraint = layoutConstraint
                break
            case .Right, .RightMargin, .Trailing, .TrailingMargin:
                self.rightConstraint = layoutConstraint
                break
            case .BottomMargin, .Bottom, .Baseline, .FirstBaseline:
                self.bottomConstraint = layoutConstraint
                break
            default:
                break
            }
        }
        
        let color = UIColor.blackColor().colorWithAlphaComponent(0.7)
        
        let topView = UIView()
        self.addSubview(topView)
        topView.backgroundColor = color
        
        topView.autoPinEdge(.Left, toEdge: .Left, ofView: self)
        topView.autoPinEdge(.Right, toEdge: .Right, ofView: self)
        topView.autoPinEdge(.Top, toEdge: .Top, ofView: self)
        topView.autoPinEdge(.Bottom, toEdge: .Top, ofView: cropView)
        
        
        let bottomView = UIView()
        self.addSubview(bottomView)
        bottomView.backgroundColor = color
        
        bottomView.autoPinEdge(.Left, toEdge: .Left, ofView: self)
        bottomView.autoPinEdge(.Right, toEdge: .Right, ofView: self)
        bottomView.autoPinEdge(.Top, toEdge: .Bottom, ofView: cropView)
        bottomView.autoPinEdge(.Bottom, toEdge: .Bottom, ofView: self)
        
        let leftView = UIView()
        self.addSubview(leftView)
        leftView.backgroundColor = color
        
        leftView.autoPinEdge(.Left, toEdge: .Left, ofView: self)
        leftView.autoPinEdge(.Right, toEdge: .Left, ofView: cropView)
        leftView.autoPinEdge(.Top, toEdge: .Bottom, ofView: topView)
        leftView.autoPinEdge(.Bottom, toEdge: .Top, ofView: bottomView)
        
        let rightView = UIView()
        self.addSubview(rightView)
        rightView.backgroundColor = color
        
        rightView.autoPinEdge(.Left, toEdge: .Right, ofView: cropView)
        rightView.autoPinEdge(.Right, toEdge: .Right, ofView: self)
        rightView.autoPinEdge(.Top, toEdge: .Bottom, ofView: topView)
        rightView.autoPinEdge(.Bottom, toEdge: .Top, ofView: bottomView)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: "didPan:")
        self.addGestureRecognizer(panGesture)
        
        self.addCorners()
        
        self.bringSubviewToFront(cropView)
        
        progressView = UIView()
        cropView.addSubview(progressView)
        progressView.autoPinEdgeToSuperviewEdge(.Top)
        progressView.autoPinEdgeToSuperviewEdge(.Bottom)
        progressLeftLayoutConstraint = progressView.autoPinEdgeToSuperviewEdge(.Left)
        progressView.autoSetDimension(.Width, toSize: 3)
        progressView.backgroundColor = self.progressColor.colorWithAlphaComponent(0.5)
        progressView.hidden = true
        
        hintLabel = UILabel()
        hintLabel.backgroundColor = UIColor.blackColor().colorWithAlphaComponent(0.5)
        hintLabel.numberOfLines = 0
        hintLabel.textColor = UIColor.whiteColor()
        hintLabel.text = "Align text to top left corner"
        hintLabel.font = UIFont.systemFontOfSize(20)
        hintLabel.textAlignment = .Center
        hintLabel.adjustsFontSizeToFitWidth = true
        cropView.addSubview(hintLabel)
        hintLabel.autoPinEdgeToSuperviewEdge(.Top, withInset: 0, relation: .GreaterThanOrEqual)
        hintLabel.autoPinEdgeToSuperviewEdge(.Bottom, withInset: 0, relation: .GreaterThanOrEqual)
        hintLabel.autoPinEdgeToSuperviewEdge(.Left, withInset: 16, relation: .GreaterThanOrEqual)
        hintLabel.autoPinEdgeToSuperviewEdge(.Right, withInset: 16, relation: .GreaterThanOrEqual)
        hintLabel.autoCenterInSuperview()
        
        
    }
    
    var textScanView: RVTTextScannerView? {
        return self.superview as? RVTTextScannerView
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if let scanView = self.textScanView {
            scanView.cropRect = self.cropRect
        }
        
        self.resizeCorners()
    }
    
    
    private var maxHeight: CGFloat {
        return self.frame.size.height
    }
    private var maxWidth: CGFloat {
        return self.frame.size.width
    }
    
    private let minHeight: CGFloat = 60
    private let minWidth: CGFloat = 60
    
    private enum PanEdge {
        case Center, Left, Right, Top, Bottom, TopLeftCorner, TopRightCorner, BottomLeftCorner, BottomRightCorner, Outside
    }
    
    private func startEdgeForView(view: UIView, point: CGPoint) -> PanEdge {
        
        let topLeft = CGPointZero
        let topRight = CGPointMake(view.frame.size.width, 0)
        let bottomLeft = CGPointMake(0, view.frame.size.height)
        let bottomRight = CGPointMake(view.frame.size.width, view.frame.size.height)
        
        let threshold: CGFloat = 20
        
        if topLeft.distanceToPoint(point) < threshold*2 {
            return .TopLeftCorner
        }
        
        if topRight.distanceToPoint(point) < threshold*2 {
            return .TopRightCorner
        }
        
        if bottomLeft.distanceToPoint(point) < threshold*2 {
            return .BottomLeftCorner
        }
        
        if bottomRight.distanceToPoint(point) < threshold*2 {
            return .BottomRightCorner
        }
        
        if fabs(point.y) < threshold {
            return .Top
        }
        
        if fabs(point.x) < threshold {
            return .Left
        }
        
        if fabs(point.x - bottomRight.x) < threshold {
            return .Right
        }
        
        if fabs(point.y - bottomRight.y) < threshold {
            return .Bottom
        }
        
        if (point.x < bottomRight.x && point.x > 0 && point.y < bottomRight.y && point.y > 0) {
            return .Center
        }
        
        return .Outside
    }
    
    private var startEdge: PanEdge = .Center
    private var startPoint: CGPoint = CGPointZero
    
    func didPan(gesture: UIPanGestureRecognizer) {
        
        let translation = gesture.translationInView(self.resizedView)
        let location = gesture.locationInView(self.resizedView)
        
        var currentPosition = self.startPoint
        currentPosition.x += translation.x
        currentPosition.y += translation.y
        
        switch (gesture.state) {
        case .Began:
            self.resetStartingConstraint()
            self.startPoint = translation
            self.startEdge = self.startEdgeForView(self.resizedView, point: location)
            break
        case .Changed:
            
            self.moveEdge(self.startEdge, translation: translation)
            self.textScanView?.cancelCurrentScan = true
            
            break
        case .Cancelled:
            self.textScanView?.cancelCurrentScan = true
            break
        case .Ended:
            self.textScanView?.cancelCurrentScan = true
            break
        default:
            break
        }
    }
    
    private var topStart: CGFloat = 0
    private var bottomStart: CGFloat = 0
    private var rightStart: CGFloat = 0
    private var leftStart: CGFloat = 0
    
    private func resetStartingConstraint() {
        self.topStart = self.topConstraint.constant
        self.bottomStart = self.bottomConstraint.constant
        self.rightStart = self.rightConstraint.constant
        self.leftStart = self.leftConstraint.constant
    }
    
    private func moveEdge(edge:PanEdge, translation:CGPoint) {
        
        var nextTop = self.topStart+translation.y
        var nextLeft = self.leftStart+translation.x
        
        if nextTop < 0 {
            nextTop = 0
        }
        
        if nextLeft < 0 {
            nextLeft = 0
        }
        
        //negative
        var nextBottom = self.bottomStart+translation.y
        var nextRight = self.rightStart+translation.x
        
        
        if nextBottom > 0 {
            nextBottom = 0
        }
        
        if nextRight > 0 {
            nextRight = 0
        }
        
        let shouldMoveTop = self.frame.size.height - fabs(nextTop) - fabs(self.bottomConstraint.constant) >= self.minHeight
        let shouldMoveBottom = self.frame.size.height - fabs(nextBottom) - fabs(self.topConstraint.constant) >= self.minHeight
        let shouldMoveLeft = self.frame.size.width - fabs(nextLeft) - fabs(self.rightConstraint.constant) >= self.minWidth
        let shouldMoveRight = self.frame.size.width - fabs(nextRight) - fabs(self.leftConstraint.constant) >= self.minWidth
        
        switch edge {
        case .Top:
            if shouldMoveTop {
                self.topConstraint.constant = nextTop
            }
            
            break
        case .Bottom:
            if shouldMoveBottom {
                self.bottomConstraint.constant = nextBottom
            }
            
            break
        case .Left:
            if shouldMoveLeft {
                self.leftConstraint.constant = nextLeft
            }
            
            break
        case .Right:
            if shouldMoveRight {
                self.rightConstraint.constant = nextRight
            }
            
            break
        case .TopLeftCorner:
            
            if shouldMoveTop {
                self.topConstraint.constant = nextTop
            }
            
            if shouldMoveLeft {
                self.leftConstraint.constant = nextLeft
            }
            
            break
        case .TopRightCorner:
            
            if shouldMoveTop {
                self.topConstraint.constant = nextTop
            }
            
            if shouldMoveRight {
                self.rightConstraint.constant = nextRight
            }
            break
        case .BottomLeftCorner:
            
            if shouldMoveBottom {
                self.bottomConstraint.constant = nextBottom
            }
            
            if shouldMoveLeft {
                self.leftConstraint.constant = nextLeft
            }
            break
        case .BottomRightCorner:
            
            if shouldMoveBottom {
                self.bottomConstraint.constant = nextBottom
            }
            
            if shouldMoveRight {
                self.rightConstraint.constant = nextRight
            }
            
            break
        case .Center:
            if self.frame.size.height - nextBottom - self.topConstraint.constant >= self.minHeight {
                self.bottomConstraint.constant = nextBottom
            }
            
            if self.frame.size.width - nextRight - self.leftConstraint.constant >= self.minWidth {
                self.rightConstraint.constant = nextRight
            }
            
            if self.frame.size.height - nextTop - self.bottomConstraint.constant >= self.minHeight {
                self.topConstraint.constant = nextTop
            }
            
            if self.frame.size.width - nextLeft - self.rightConstraint.constant >= self.minWidth {
                self.leftConstraint.constant = nextLeft
            }
            break
        case .Outside:
            break
        }
        
        self.layoutIfNeeded()
    }
    
    private func addCorners() {
        
        let shapeLayer = self.cornerShapeLayer;
        shapeLayer.fillColor = UIColor.clearColor().CGColor;
        shapeLayer.strokeColor = self.edgeColor.CGColor;
        shapeLayer.lineWidth = 5.0;
        shapeLayer.fillRule = kCAFillRuleNonZero;
        
        self.resizedView.layer.addSublayer(shapeLayer)
        
        self.resizeCorners()
    }
    
    private func resizeCorners() {
        let segmentLength: CGFloat = self.minHeight/3;
        
        let width = self.resizedView.frame.size.width
        let height = self.resizedView.frame.size.height
        let x: CGFloat = 0
        let y: CGFloat = 0
        
        let path = CGPathCreateMutable();
        CGPathMoveToPoint(path, nil, segmentLength, y);
        CGPathAddLineToPoint(path, nil, x, y);
        CGPathAddLineToPoint(path, nil, x, segmentLength);
        
        CGPathMoveToPoint(path, nil, width-segmentLength, y);
        CGPathAddLineToPoint(path, nil, width, y);
        CGPathAddLineToPoint(path, nil, width, segmentLength);
        
        CGPathMoveToPoint(path, nil, width-segmentLength, height);
        CGPathAddLineToPoint(path, nil, width, height);
        CGPathAddLineToPoint(path, nil, width, height - segmentLength);
        
        CGPathMoveToPoint(path, nil, segmentLength, height);
        CGPathAddLineToPoint(path, nil, x, height);
        CGPathAddLineToPoint(path, nil, x, height - segmentLength);
        
        self.cornerShapeLayer.path = path
        self.cornerShapeLayer.frame = self.resizedView.bounds;
    }
}



extension UILabel {
    
    public func resizeFontToFit() {
        
        let maxFontSize: CGFloat = 25
        let minFontSize: CGFloat = 5
        
        self.font = UIFont(name: self.font!.fontName, size: self.binarySearchForFontSize(maxFontSize, minFontSize: minFontSize))
    }
    
    func binarySearchForFontSize(maxFontSize: CGFloat, minFontSize: CGFloat) -> CGFloat {
        
        // Find the middle
        let fontSize = (minFontSize + maxFontSize) / 2;
        // Create the font
        let font = UIFont(name:self.font.fontName, size:fontSize)
        // Create a constraint size with max height
        let constraintSize = CGSizeMake(self.frame.size.width, CGFloat.max);
        
        // Find label size for current font size
        let labelSize = self.text!.boundingRectWithSize(constraintSize, options:NSStringDrawingOptions.UsesLineFragmentOrigin, attributes:[NSFontAttributeName : font!], context:nil).size
        
        if (fontSize > maxFontSize) {
            return maxFontSize
        } else if fontSize < minFontSize {
            return minFontSize
        } else if (labelSize.height > self.frame.size.height || labelSize.width > self.frame.size.width) {
            return self.binarySearchForFontSize(maxFontSize-1, minFontSize: minFontSize)
        } else {
            return self.binarySearchForFontSize(maxFontSize, minFontSize: fontSize+1)
        }
    }
}

extension CGPoint {
    
    public func distanceToPoint(point: CGPoint) -> CGFloat {
        
        return CGFloat(hypotf(Float(self.x - point.x), Float(self.y - point.y)))
    }
}


extension UIImage {
    
    public func imageWithSize(var newSize: CGSize, contentMode: UIViewContentMode = UIViewContentMode.ScaleAspectFit) -> UIImage {
        
        let imgRef = self.CGImage;
        // the below values are regardless of orientation : for UIImages from Camera, width>height (landscape)
        let  originalSize = CGSizeMake(CGFloat(CGImageGetWidth(imgRef)), CGFloat(CGImageGetHeight(imgRef))); // not equivalent to self.size (which is dependant on the imageOrientation)!
        
        var boundingSize = newSize
        
        // adjust boundingSize to make it independant on imageOrientation too for farther computations
        let  imageOrientation = self.imageOrientation;
        
        switch (imageOrientation) {
        case .Left, .Right, .RightMirrored, .LeftMirrored:
            boundingSize = CGSizeMake(boundingSize.height, boundingSize.width);
            break
        default:
            // NOP
            break;
        }
        
        let wRatio = boundingSize.width / originalSize.width;
        let hRatio = boundingSize.height / originalSize.height;
        
        switch contentMode {
            
        case .ScaleAspectFit:
            
            if (wRatio < hRatio) {
                newSize = CGSizeMake(boundingSize.width, floor(originalSize.height * wRatio))
            } else {
                newSize = CGSizeMake(floor(originalSize.width * hRatio), boundingSize.height);
            }
            
        case .ScaleAspectFill:
            
            if (wRatio > hRatio) {
                newSize = CGSizeMake(boundingSize.width, floor(originalSize.height * wRatio))
            } else {
                newSize = CGSizeMake(floor(originalSize.width * hRatio), boundingSize.height);
            }
            
        default:
            break
        }
        
        /* Don't resize if we already meet the required destination size. */
        if CGSizeEqualToSize(originalSize, newSize) {
            return self;
        }
        
        let scaleRatioWidth = newSize.width / originalSize.width
        let scaleRatioHeight = newSize.height / originalSize.height
        
        var transform = CGAffineTransformIdentity;
        
        switch(imageOrientation) {
            
        case .Up: //EXIF = 1
            transform = CGAffineTransformIdentity;
            break;
            
        case .UpMirrored: //EXIF = 2
            transform = CGAffineTransformMakeTranslation(originalSize.width, 0.0);
            transform = CGAffineTransformScale(transform, -1.0, 1.0);
            break;
            
        case .Down: //EXIF = 3
            transform = CGAffineTransformMakeTranslation(originalSize.width, originalSize.height);
            transform = CGAffineTransformRotate(transform, CGFloat(M_PI));
            break;
            
        case . DownMirrored: //EXIF = 4
            transform = CGAffineTransformMakeTranslation(0.0, originalSize.height);
            transform = CGAffineTransformScale(transform, 1.0, -1.0);
            break;
            
        case . LeftMirrored: //EXIF = 5
            newSize = CGSizeMake(newSize.height, newSize.width);
            transform = CGAffineTransformMakeTranslation(originalSize.height, originalSize.width);
            transform = CGAffineTransformScale(transform, -1.0, 1.0);
            transform = CGAffineTransformRotate(transform, 3.0 * CGFloat(M_PI_2));
            break;
            
        case . Left: //EXIF = 6
            newSize = CGSizeMake(newSize.height, newSize.width);
            transform = CGAffineTransformMakeTranslation(0.0, originalSize.width);
            transform = CGAffineTransformRotate(transform, 3.0 * CGFloat(M_PI_2));
            break;
            
        case .RightMirrored: //EXIF = 7
            newSize = CGSizeMake(newSize.height, newSize.width);
            transform = CGAffineTransformMakeScale(-1.0, 1.0);
            transform = CGAffineTransformRotate(transform, CGFloat(M_PI_2));
            break;
            
        case . Right: //EXIF = 8
            newSize = CGSizeMake(newSize.height, newSize.width);
            transform = CGAffineTransformMakeTranslation(originalSize.height, 0.0);
            transform = CGAffineTransformRotate(transform, CGFloat(M_PI_2));
            break;
        }
        
        /////////////////////////////////////////////////////////////////////////////
        // The actual resize: draw the image on a new context, applying a transform matrix
        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale);
        
        let context = UIGraphicsGetCurrentContext();
        
        if (imageOrientation == . Right || imageOrientation == . Left) {
            CGContextScaleCTM(context, -scaleRatioWidth, scaleRatioHeight);
            CGContextTranslateCTM(context, -originalSize.height, 0);
        } else {
            CGContextScaleCTM(context, scaleRatioWidth, -scaleRatioHeight);
            CGContextTranslateCTM(context, 0, -originalSize.height);
        }
        
        CGContextConcatCTM(context, transform);
        
        // we use originalSize (and not newSize) as the size to specify is in user space (and we use the CTM to apply a scaleRatio)
        CGContextDrawImage(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, originalSize.width, originalSize.height), imgRef);
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return resizedImage;
    }
}
