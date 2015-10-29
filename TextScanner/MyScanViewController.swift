//
//  MyScanViewController.swift
//  PassportOCR
//
//  Created by Edwin Vermeer on 9/7/15.
//  Copyright (c) 2015 mirabeau. All rights reserved.
//

import Foundation

class MyScanViewController: UIViewController, RVTTextScannerViewDelegate {
    
    @IBOutlet weak var textScannerView: RVTTextScannerView!
    /// Delegate set by the calling controler so that we can pass on ProcessMRZ events.
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var label: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.textScannerView.delegate = self
        self.textScannerView.showCropView = true
        self.textScannerView.cropView?.edgeColor = UIColor.lightGrayColor()
        self.textScannerView.cropView?.progressColor = UIColor.redColor()
        self.textScannerView.startScan()
    }
    
    @IBAction func dismiss(sender: AnyObject) {
        self.dismissViewControllerAnimated(true, completion: nil)
    }
    
     override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.Portrait
    }
    
     override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    func scannerDidRecognizeText(scanner: RVTTextScannerView, textResult: RVTTextResult, image: UIImage?) {
        
    }
    
    func scannerDidFindCommontextResult(scanner: RVTTextScannerView, textResult: RVTTextResult, image: UIImage?) {
        
        self.label.text = textResult.lines.first
        self.imageView.image = image
        print(textResult.text, textResult.lines.first, textResult.whiteSpacedComponents)
        self.view.layoutIfNeeded()
        
//        self.textScannerView.stopScan()
//        self.dismissViewControllerAnimated(true, completion: nil)
    }
}

