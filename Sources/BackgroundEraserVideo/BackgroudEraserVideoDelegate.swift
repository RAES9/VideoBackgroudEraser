//
//  File.swift
//  
//
//  Created by Tribal on 4/08/22.
//

import Foundation

public protocol BackgroudEraserVideoDelegate {
    
    func didFinishToProcesingVideo(url: URL)
    func procesingVideo(percentage: Double)
}
