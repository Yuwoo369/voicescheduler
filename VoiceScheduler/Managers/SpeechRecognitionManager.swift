// SpeechRecognitionManager.swift
// 음성을 텍스트로 변환하는 기능을 담당합니다.
// 애플의 Speech 프레임워크를 사용합니다.

import Foundation
import Speech        // 음성 인식 프레임워크
import AVFoundation  // 오디오 녹음 프레임워크
import Combine       // @Published 사용을 위한 프레임워크

// ============================================================
// MARK: - 음성 인식 관리자
// ============================================================

// ObservableObject: 데이터가 바뀌면 화면이 자동 업데이트됨
class SpeechRecognitionManager: NSObject, ObservableObject {

    // --------------------------------------------------------
    // MARK: - 외부에서 읽을 수 있는 데이터 (@Published)
    // --------------------------------------------------------

    // 현재까지 인식된 텍스트
    @Published var transcribedText: String = ""

    // 현재 녹음 중인지 여부
    @Published var isRecording: Bool = false

    // 음성 인식 권한이 있는지 여부
    @Published var hasPermission: Bool = false

    // 에러 메시지
    @Published var errorMessage: String?

    // 현재 음성 입력의 크기 (볼륨) - 애니메이션용
    @Published var audioLevel: Float = 0.0

    // --------------------------------------------------------
    // MARK: - 내부 변수들 (private = 이 클래스 안에서만 사용)
    // --------------------------------------------------------

    // 음성 인식 엔진
    private var speechRecognizer: SFSpeechRecognizer?

    // 음성 인식 요청 객체
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    // 녹음 세션 세대 카운터 (이전 세션의 비동기 콜백이 새 세션을 방해하지 않도록)
    private var taskGeneration: Int = 0

    // 음성 인식 작업
    private var recognitionTask: SFSpeechRecognitionTask?

    // 오디오 엔진 (마이크 입력 처리)
    private let audioEngine = AVAudioEngine()

    // --------------------------------------------------------
    // MARK: - 초기화
    // --------------------------------------------------------

    override init() {
        super.init()

        // 앱 언어에 맞는 음성 인식기 설정
        speechRecognizer = SFSpeechRecognizer(locale: speechLocale)

        // 음성 인식 권한 요청
        requestPermission()
    }

    // --------------------------------------------------------
    // MARK: - 언어 로케일 매핑
    // --------------------------------------------------------

    /// 앱의 현재 언어 설정에 맞는 음성 인식 Locale 반환
    private var speechLocale: Locale {
        let lang = LocalizationManager.shared.currentLanguage
        switch lang {
        case "ko": return Locale(identifier: "ko-KR")
        case "ja": return Locale(identifier: "ja-JP")
        case "zh-Hans": return Locale(identifier: "zh-CN")
        case "pt-BR": return Locale(identifier: "pt-BR")
        case "hi": return Locale(identifier: "hi-IN")
        case "es": return Locale(identifier: "es-ES")
        default: return Locale(identifier: "en-US")
        }
    }

    // --------------------------------------------------------
    // MARK: - 권한 요청
    // --------------------------------------------------------

    /// 음성 인식과 마이크 사용 권한을 요청하는 함수
    func requestPermission() {

        // 1. 음성 인식 권한 요청
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            // weak self: 메모리 누수 방지를 위한 패턴
            // (클래스가 사라졌는데 이 코드가 실행되면 크래시 날 수 있어서)

            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    // 권한 허용됨
                    self?.hasPermission = true
                case .denied:
                    // 사용자가 거부함
                    self?.errorMessage = "speech_permission_denied".localized
                    self?.hasPermission = false
                case .restricted:
                    // 기기 제한 (예: 자녀 보호 설정)
                    self?.errorMessage = "speech_permission_restricted".localized
                    self?.hasPermission = false
                case .notDetermined:
                    // 아직 결정 안됨
                    self?.hasPermission = false
                @unknown default:
                    self?.hasPermission = false
                }
            }
        }

        // 2. 마이크 권한 요청
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            if !granted {
                DispatchQueue.main.async {
                    self?.errorMessage = "microphone_permission_required".localized
                }
            }
        }
    }

    // --------------------------------------------------------
    // MARK: - 녹음 시작
    // --------------------------------------------------------

    /// 음성 녹음을 시작하고 실시간으로 텍스트로 변환합니다
    /// - Returns: 녹음 시작 성공 여부
    @discardableResult
    func startRecording() -> Bool {
        // 권한 체크
        guard hasPermission else {
            errorMessage = "speech_no_permission".localized
            return false
        }

        // 이전 세션 완전 정리 (어떤 상태든 안전하게)
        cleanupRecordingSession()

        // 앱 언어가 바뀌었을 수 있으므로 음성 인식기 로케일 갱신
        speechRecognizer = SFSpeechRecognizer(locale: speechLocale)

        // 음성 인식기 사용 가능 여부 체크
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "speech_unavailable".localized
            return false
        }

        // 이전 텍스트 초기화
        transcribedText = ""
        errorMessage = nil

        // 오디오 세션 설정
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "audio_session_error".localized
            return false
        }

        // 음성 인식 요청 생성
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        let inputNode = audioEngine.inputNode

        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "speech_recognition_failed".localized
            return false
        }

        // 실시간 결과 받기 설정
        recognitionRequest.shouldReportPartialResults = true

        // 세대 카운터 증가 (이전 세션의 콜백 무시용)
        taskGeneration += 1
        let currentGeneration = taskGeneration

        // 음성 인식 시작
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self, self.taskGeneration == currentGeneration else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
        }

        // recognitionTask 생성 실패 체크
        guard recognitionTask != nil else {
            errorMessage = "speech_recognition_failed".localized
            cleanupRecordingSession()
            return false
        }

        // 오디오 포맷 설정
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        // 오디오 엔진 시작
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            return true
        } catch {
            errorMessage = "audio_engine_error".localized
            cleanupRecordingSession()
            return false
        }
    }

    // --------------------------------------------------------
    // MARK: - 녹음 중지
    // --------------------------------------------------------

    /// 음성 녹음을 중지합니다
    func stopRecording() {
        cleanupRecordingSession()
        isRecording = false
        audioLevel = 0
    }

    // --------------------------------------------------------
    // MARK: - 세션 정리 (공통)
    // --------------------------------------------------------

    /// 오디오 엔진, 인식 요청, 인식 작업을 모두 정리합니다
    private func cleanupRecordingSession() {
        // 세대 카운터 증가 → 기존 콜백 무효화
        taskGeneration += 1

        // 오디오 엔진 중지 + 탭 제거
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        // 음성 인식 요청/작업 정리
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // 오디오 세션 비활성화 (다음 세션을 위해 리소스 해제)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // --------------------------------------------------------
    // MARK: - 오디오 레벨 계산
    // --------------------------------------------------------

    /// 현재 마이크 입력의 볼륨 크기를 계산합니다 (애니메이션용)
    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }

        // RMS(Root Mean Square) 계산 - 오디오 신호의 평균 크기
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))

        // 데시벨로 변환하고 정규화
        let avgPower = 20 * log10(rms)
        let normalizedValue = max(0, min(1, (avgPower + 50) / 50))

        DispatchQueue.main.async {
            self.audioLevel = normalizedValue
        }
    }
}
