import WidgetKit
import SwiftUI

// ============================================================
// MARK: - Widget Localization
// ============================================================

/// 위젯 전용 로컬라이제이션 (위젯은 별도 extension이므로 메인 앱의 Localizable.strings 접근 불가)
private enum WidgetL10n {
    static var title: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "ko": return "음성 일정"
        case "ja": return "音声スケジュール"
        case "zh": return "语音日程"
        case "es": return "Agenda de Voz"
        case "fr": return "Agenda Vocal"
        case "pt": return "Agenda por Voz"
        case "hi": return "वॉइस शेड्यूल"
        default: return "Voice Schedule"
        }
    }

    static var subtitle: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "ko": return "음성으로 일정 등록"
        case "ja": return "音声で予定を登録"
        case "zh": return "语音添加日程"
        case "es": return "Añadir evento por voz"
        case "fr": return "Ajouter un événement vocal"
        case "pt": return "Adicionar evento por voz"
        case "hi": return "आवाज़ से शेड्यूल करें"
        default: return "Schedule with Voice"
        }
    }

    static var tapToRecord: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "ko": return "탭하여 음성 녹음 시작"
        case "ja": return "タップして録音開始"
        case "zh": return "点击开始录音"
        case "es": return "Toca para grabar"
        case "fr": return "Appuyez pour enregistrer"
        case "pt": return "Toque para gravar"
        case "hi": return "रिकॉर्ड करने के लिए टैप करें"
        default: return "Tap to start recording"
        }
    }

    static var description: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "ko": return "탭하여 음성으로 일정을 빠르게 등록하세요."
        case "ja": return "タップして音声で素早く予定を登録。"
        case "zh": return "点击用语音快速添加日程。"
        case "es": return "Toca para añadir eventos rápidamente con voz."
        case "fr": return "Appuyez pour ajouter rapidement des événements par la voix."
        case "pt": return "Toque para adicionar eventos rapidamente por voz."
        case "hi": return "आवाज़ से जल्दी शेड्यूल जोड़ने के लिए टैप करें।"
        default: return "Tap to quickly add events with your voice."
        }
    }
}

// ============================================================
// MARK: - Widget Timeline Provider
// ============================================================

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = SimpleEntry(date: Date())
        // 위젯은 정적이므로 자주 업데이트할 필요 없음
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// ============================================================
// MARK: - Timeline Entry
// ============================================================

struct SimpleEntry: TimelineEntry {
    let date: Date
}

// ============================================================
// MARK: - Widget Entry View
// ============================================================

struct VoiceSchedulerWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView()
        case .systemMedium:
            MediumWidgetView()
        default:
            SmallWidgetView()
        }
    }
}

// ============================================================
// MARK: - Small Widget View
// ============================================================

struct SmallWidgetView: View {
    var body: some View {
        ZStack {
            // 배경 그라데이션
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.4, green: 0.6, blue: 1.0),
                    Color(red: 0.6, green: 0.4, blue: 0.9)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                // 마이크 아이콘
                Image(systemName: "mic.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.white)

                // 텍스트
                Text(WidgetL10n.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .widgetURL(URL(string: "voicescheduler://startRecording"))
    }
}

// ============================================================
// MARK: - Medium Widget View
// ============================================================

struct MediumWidgetView: View {
    var body: some View {
        ZStack {
            // 배경 그라데이션
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.4, green: 0.6, blue: 1.0),
                    Color(red: 0.6, green: 0.4, blue: 0.9)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 20) {
                // 마이크 아이콘
                Image(systemName: "mic.fill")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 6) {
                    Text(WidgetL10n.subtitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text(WidgetL10n.tapToRecord)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding()
        }
        .widgetURL(URL(string: "voicescheduler://startRecording"))
    }
}

// ============================================================
// MARK: - Widget Configuration
// ============================================================

struct VoiceSchedulerWidget: Widget {
    let kind: String = "VoiceSchedulerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                VoiceSchedulerWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                VoiceSchedulerWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName(WidgetL10n.title)
        .description(WidgetL10n.description)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ============================================================
// MARK: - Widget Bundle (Entry Point)
// ============================================================

@main
struct VoiceSchedulerWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoiceSchedulerWidget()
    }
}

// ============================================================
// MARK: - Preview
// ============================================================

#Preview(as: .systemSmall) {
    VoiceSchedulerWidget()
} timeline: {
    SimpleEntry(date: .now)
}

#Preview(as: .systemMedium) {
    VoiceSchedulerWidget()
} timeline: {
    SimpleEntry(date: .now)
}
