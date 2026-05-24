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
    var isGenerating: Bool = false
    var onStop: (() -> Void)? = nil
    
    private let logger = Logger(subsystem: "com.omniai.ui", category: "ChatInputBar")
    
    @State private var messageText: String = ""
    @State private var attachments: [InputAttachment] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var capturedImageData: Data?
    @State private var showFileImporter = false
    @State private var previewImageData: Data?
    
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
                    placeholder: L10n.string("chat.input.placeholder"),
                    isFocused: $isFocused
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 38)
#else
                TextField("chat.input.placeholder", text: $messageText, axis: .vertical)
                    .focused($isFocused)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 14)
                    .lineLimit(1...5)
#endif
                
                HStack {
                    Menu {
                        Button(action: { showFileImporter = true }) {
                            Label("attachment.file", systemImage: "doc")
                        }
                        
                        Button(action: { showPhotoPicker = true }) {
                            Label("attachment.photo", systemImage: "photo")
                        }
                        
#if canImport(UIKit)
                        Button(action: { showCamera = true }) {
                            Label("attachment.camera", systemImage: "camera")
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
                        if isGenerating {
                            onStop?()
                        } else if canSend {
                            onSend?(messageText, attachments)
                            messageText = ""
                            attachments.removeAll()
                        } else {
                            logger.debug("Start voice input")
                        }
                    }){
                        Image(systemName: isGenerating ? "stop.fill" : (canSend ? "arrow.up" : "mic.fill"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(isGenerating ? Color.orange : (canSend ? Color.black : Color.gray)))
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
#if canImport(UIKit)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(imageData: $capturedImageData)
                .ignoresSafeArea()
        }
#endif
        .onChange(of: capturedImageData) { _, newData in
            if let data = newData,
               let compressed = ImageProcessor.compressImage(data) {
                let thumb = ImageProcessor.generateThumbnail(data)
                attachments.append(InputAttachment(
                    type: .image,
                    name: "IMG_\(Int(Date().timeIntervalSince1970)).jpg",
                    data: compressed,
                    thumbnailData: thumb
                ))
                capturedImageData = nil
            }
        }
        .sheet(item: Binding(
            get: { previewImageData.map { ImagePreviewData(data: $0) } },
            set: { previewImageData = $0?.data }
        )) { preview in
            ImageViewer(imageData: preview.data)
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
        if attachment.type == .image, let data = attachment.thumbnailData ?? attachment.data {
#if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        if let fullData = attachment.data { previewImageData = fullData }
                    }
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
            let compressed = ImageProcessor.compressImage(data)
            let thumb = ImageProcessor.generateThumbnail(data)
            let name = item.itemIdentifier ?? "photo_\(Int(Date().timeIntervalSince1970)).jpg"
            attachments.append(InputAttachment(
                type: .image,
                name: name,
                data: compressed,
                thumbnailData: thumb
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
                if type == .image, let data = fileData {
                    let compressed = ImageProcessor.compressImage(data)
                    let thumb = ImageProcessor.generateThumbnail(data)
                    attachments.append(InputAttachment(
                        type: type,
                        name: name,
                        url: url,
                        data: compressed,
                        thumbnailData: thumb
                    ))
                } else {
                    attachments.append(InputAttachment(
                        type: type,
                        name: name,
                        url: url,
                        data: fileData
                    ))
                }
            }
        case .failure(let error):
            logger.error("File selection failed: \(error.localizedDescription)")
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

private struct ImagePreviewData: Identifiable {
    let id = UUID()
    let data: Data
}
