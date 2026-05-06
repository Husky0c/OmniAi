//
//  ChatInputBar.swift
//  OmniAi
//
//  Created by 张益龙 on 2026/4/20.
//

import SwiftUI
import SwiftData
import OSLog
import PhotosUI
import UniformTypeIdentifiers

struct ChatInputBar: View{
    var onSend: ((String, [InputAttachment]) -> Void)?
    
    private let logger = Logger(subsystem: "com.omniai.ui", category: "ChatInputBar")
    
    @State private var messageText: String = ""
    @State private var attachments: [InputAttachment] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var capturedImageData: Data?
    @State private var showFileImporter = false
    
#if canImport(UIKit)
    @State private var isFocused: Bool = false
#else
    @FocusState private var isFocused: Bool
#endif
    
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }
    
    var body: some View{
        VStack(spacing: 8){
            VStack(spacing: 4){
                if !attachments.isEmpty {
                    attachmentPreviewArea
                }
                
#if canImport(UIKit)
                DynamicHeightTextView(
                    text: $messageText,
                    placeholder: "聊你所想",
                    isFocused: $isFocused
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 38)
#else
                TextField("聊你所想", text: $messageText, axis: .vertical)
                    .focused($isFocused)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 14)
                    .lineLimit(1...5)
#endif
                
                HStack {
                    Menu {
                        Button(action: { showFileImporter = true }) {
                            Label("文件", systemImage: "doc")
                        }
                        
                        Button(action: { showPhotoPicker = true }) {
                            Label("照片", systemImage: "photo")
                        }
                        
#if canImport(UIKit)
                        Button(action: { showCamera = true }) {
                            Label("相机", systemImage: "camera")
                        }
#endif
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(Circle().fill(Color.gray.opacity(0.1)))
                    }
                    .compositingGroup()
                    
                    Spacer()
                    
                    Button(action: {
                        if canSend {
                            onSend?(messageText, attachments)
                            messageText = ""
                            attachments.removeAll()
                        } else {
                            logger.debug("开始语音")
                        }
                    }){
                        Image(systemName: canSend ? "arrow.up" : "mic.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(canSend ? Color.black : Color.gray))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .containerRelativeFrame(.horizontal) { length, _ in
            min(length * 0.92, 600)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, matching: .any(of: [.images]))
        .onChange(of: selectedPhotos) { _, _ in
            Task { await handleSelectedPhotos() }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            handleFileImporter(result)
        }
        .fullScreenCover(isPresented: $showCamera) {
#if canImport(UIKit)
            CameraPicker(imageData: $capturedImageData)
                .ignoresSafeArea()
#endif
        }
        .onChange(of: capturedImageData) { _, newData in
            if let data = newData {
                attachments.append(InputAttachment(
                    type: .image,
                    name: "IMG_\(Int(Date().timeIntervalSince1970)).jpg",
                    data: data
                ))
                capturedImageData = nil
            }
        }
    }
    
    @ViewBuilder
    private var attachmentPreviewArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    attachmentThumbnail(attachment)
                        .overlay(alignment: .topTrailing) {
                            Button(action: {
                                attachments.removeAll { $0.id == attachment.id }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                                    .offset(x: 4, y: -4)
                            }
                            .buttonStyle(.plain)
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .frame(height: 70)
    }
    
    @ViewBuilder
    private func attachmentThumbnail(_ attachment: InputAttachment) -> some View {
        if attachment.type == .image, let data = attachment.data {
#if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                fallbackThumbnail(attachment)
            }
#else
            fallbackThumbnail(attachment)
#endif
        } else {
            fallbackThumbnail(attachment)
        }
    }

    private func fallbackThumbnail(_ attachment: InputAttachment) -> some View {
        VStack(spacing: 2) {
            Image(systemName: iconForType(attachment.type))
                .font(.title3)
            Text(attachment.name)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 50)
        }
        .frame(width: 50, height: 50)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func iconForType(_ type: AttachmentType) -> String {
        switch type {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "doc.text"
        case .document: return "doc"
        case .other: return "questionmark.diamond"
        }
    }
    
    private func handleSelectedPhotos() async {
        for item in selectedPhotos {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let name = item.itemIdentifier ?? "photo_\(Int(Date().timeIntervalSince1970)).jpg"
            attachments.append(InputAttachment(
                type: .image,
                name: name,
                data: data
            ))
        }
        selectedPhotos.removeAll()
    }
    
    private func handleFileImporter(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let ext = url.pathExtension
                let type = AttachmentType.from(extension: ext)
                let name = url.lastPathComponent
                let fileData = try? Data(contentsOf: url)
                attachments.append(InputAttachment(
                    type: type,
                    name: name,
                    url: url,
                    data: fileData
                ))
            }
        case .failure(let error):
            logger.error("文件选择失败: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        
        VStack {
            Spacer()
            ChatInputBar()
        }
    }
}
