import AppKit
import LinkPresentation
import SwiftUI

/// 링크 프리뷰 메타데이터(제목·파비콘) 로더. 프리뷰가 열릴 때만 해당 URL 에 요청한다 (백그라운드 페치 없음).
@MainActor
final class LinkPreviewLoader: ObservableObject {
    static let shared = LinkPreviewLoader()

    enum State {
        case loading
        case loaded(title: String?, icon: NSImage?)
        case failed
    }

    @Published private(set) var entries: [String: State] = [:]

    func load(_ urlString: String) {
        guard entries[urlString] == nil,
              let url = URL(string: urlString) else { return }
        entries[urlString] = .loading

        let provider = LPMetadataProvider()
        provider.timeout = 6
        provider.startFetchingMetadata(for: url) { metadata, _ in
            guard let metadata else {
                Task { @MainActor in
                    LinkPreviewLoader.shared.entries[urlString] = .failed
                }
                return
            }
            let title = metadata.title
            if let iconProvider = metadata.iconProvider {
                _ = iconProvider.loadObject(ofClass: NSImage.self) { image, _ in
                    Task { @MainActor in
                        LinkPreviewLoader.shared.entries[urlString] = .loaded(title: title, icon: image as? NSImage)
                    }
                }
            } else {
                Task { @MainActor in
                    LinkPreviewLoader.shared.entries[urlString] = .loaded(title: title, icon: nil)
                }
            }
        }
    }
}

/// 링크 항목의 카드형 프리뷰: 파비콘 + 페이지 제목 + URL
struct LinkPreviewView: View {
    let urlString: String
    @ObservedObject private var loader = LinkPreviewLoader.shared

    private var host: String {
        URL(string: urlString)?.host() ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                iconView
                VStack(alignment: .leading, spacing: 2) {
                    titleView
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            Text(urlString)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
        .onAppear { loader.load(urlString) }
    }

    @ViewBuilder
    private var iconView: some View {
        switch loader.entries[urlString] {
        case .loaded(_, let icon?) :
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        default:
            Image(systemName: "link.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch loader.entries[urlString] {
        case .loading, .none:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("제목 불러오는 중…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        case .loaded(let title?, _) where !title.isEmpty:
            Text(title)
                .font(.headline)
                .lineLimit(2)
        default:
            Text(host.isEmpty ? urlString : host)
                .font(.headline)
                .lineLimit(1)
        }
    }
}
