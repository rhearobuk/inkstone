import AuthorData
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

struct GalleryView: View {
    @ObservedObject var controller: WorkspaceController

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)
    ]

    var body: some View {
        if controller.galleryItems.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                Text("No Images")
                    .font(.title2)
                Text("Imported images will appear here.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Gallery")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(controller.galleryItems, id: \.id) { item in
                        Button {
                            controller.selection = .galleryItem(item.id)
                        } label: {
                            GalleryThumbnail(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Gallery")
        }
    }
}

struct GalleryItemEditor: View {
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        if let item = controller.selectedGalleryItem {
            VStack(spacing: 0) {
                GalleryImage(data: item.resource.data)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                Form {
                    TextField(
                        "Title",
                        text: Binding(
                            get: { item.title },
                            set: { controller.updateGalleryItem(title: $0, caption: item.caption) }
                        )
                    )
                    TextField(
                        "Caption",
                        text: Binding(
                            get: { item.caption ?? "" },
                            set: { controller.updateGalleryItem(title: item.title, caption: $0) }
                        ),
                        axis: .vertical
                    )
                    if let sourceDocument = item.sourceDocument {
                        LabeledContent("Imported from", value: sourceDocument.title)
                    }
                }
                .formStyle(.grouped)
                .frame(maxHeight: 220)
            }
            .navigationTitle(item.title)
        }
    }
}

private struct GalleryThumbnail: View {
    let item: GalleryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GalleryImage(data: item.resource.data)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            if let caption = item.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct LinkedGalleryItemsView: View {
    let items: [GalleryItem]
    let onSelect: (GalleryItem) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(items, id: \.id) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            GalleryImage(data: item.resource.data)
                                .frame(width: 160, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct GalleryImage: View {
    let data: Data?

    var body: some View {
        Group {
            #if os(macOS)
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
            #elseif os(iOS) || os(visionOS)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo.badge.exclamationmark")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
