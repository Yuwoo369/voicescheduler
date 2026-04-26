// GeminiService.swift
// Google Gemini AI API를 사용하여 음성 텍스트를 분석하고
// 할 일 목록과 우선순위를 추출합니다.

import Foundation

// ============================================================
// MARK: - Gemini 서비스 클래스
// ============================================================

class GeminiService {

    // Singleton 패턴: 앱 전체에서 하나의 인스턴스만 사용
    // GeminiService.shared로 어디서든 접근 가능
    static let shared = GeminiService()

    // private init: 외부에서 새 인스턴스를 만들 수 없게 함
    private init() {}

    // --------------------------------------------------------
    // MARK: - 디버그 로깅 (개발 빌드 전용)
    // --------------------------------------------------------
    #if DEBUG
    static func writeDebugLog(_ message: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let logURL = docs.appendingPathComponent("gemini_debug.log")
        let entry = "=== \(Date()) ===\n\(message)\n\n"
        guard let data = entry.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
    #endif

    // --------------------------------------------------------
    // MARK: - API 설정
    // --------------------------------------------------------

    // Gemini API 키 (SecretsManager에서 안전하게 로드)
    private var apiKey: String {
        return SecretsManager.shared.geminiAPIKey
    }

    // API 엔드포인트 URL
    // gemini-flash-latest 모델 사용 (최신 안정 버전)
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent"

    // --------------------------------------------------------
    // MARK: - Rate Limit 관리
    // --------------------------------------------------------

    // 마지막 API 호출 시간
    private var lastAPICallTime: Date?

    // 최소 호출 간격 (초) - rate limit 방지
    private let minCallInterval: TimeInterval = 3.0

    // Rate limit 발생 후 대기 시간 (초)
    private var rateLimitCooldown: TimeInterval = 0

    // Rate limit 발생 시간
    private var rateLimitHitTime: Date?

    // 현재 요청 진행 중 여부
    private var isRequestInProgress = false

    // 대기 중인 요청 큐
    private var pendingRequests: [(String, (Result<[TodoItem], Error>) -> Void)] = []

    // --------------------------------------------------------
    // MARK: - 할 일 분석 함수
    // --------------------------------------------------------

    // 최대 재시도 횟수
    private let maxRetries = 5

    /// 음성으로 입력받은 텍스트를 분석하여 할 일 목록을 추출합니다
    /// - Parameters:
    ///   - text: 사용자가 말한 원본 텍스트
    ///   - completion: 결과를 받을 콜백 함수 (성공 시 TodoItem 배열, 실패 시 Error)
    func analyzeTasks(text: String, completion: @escaping (Result<[TodoItem], Error>) -> Void) {

        #if DEBUG
        GeminiService.writeDebugLog("▶️ analyzeTasks 요청 시작\n입력: \(text)")
        #endif

        // ⚠️ 안전장치: API 사용 가능 여부 확인
        let usageGuard = APIUsageGuard.shared
        let (allowed, reason) = usageGuard.canMakeRequest()

        if !allowed {
            #if DEBUG
            print("🛡️ API 요청 차단됨: \(reason ?? "unknown")")
            GeminiService.writeDebugLog("🛡️ API 요청 차단됨: \(reason ?? "unknown")")
            #endif
            completion(.failure(GeminiError.usageBlocked(reason ?? "Usage blocked")))
            return
        }

        // 요청 시작 기록
        usageGuard.recordRequestStart()

        // Rate limit 쿨다운 체크
        if let hitTime = rateLimitHitTime {
            let elapsed = Date().timeIntervalSince(hitTime)
            if elapsed < rateLimitCooldown {
                let remaining = Int(rateLimitCooldown - elapsed)
                #if DEBUG
                print("⏳ Rate limit 쿨다운 중... \(remaining)초 남음")
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(remaining) + 1) {
                    self.analyzeTasks(text: text, completion: completion)
                }
                return
            } else {
                // 쿨다운 종료
                rateLimitHitTime = nil
                rateLimitCooldown = 0
            }
        }

        // 최소 호출 간격 체크
        if let lastCall = lastAPICallTime {
            let elapsed = Date().timeIntervalSince(lastCall)
            if elapsed < minCallInterval {
                let waitTime = minCallInterval - elapsed
                #if DEBUG
                print("⏳ API 호출 간격 대기... \(String(format: "%.1f", waitTime))초")
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + waitTime) {
                    self.analyzeTasks(text: text, completion: completion)
                }
                return
            }
        }

        // 이미 요청 진행 중이면 큐에 추가
        if isRequestInProgress {
            #if DEBUG
            print("📋 요청 대기열에 추가됨")
            #endif
            pendingRequests.append((text, completion))
            return
        }

        isRequestInProgress = true
        lastAPICallTime = Date()

        // 실제 API 호출 실행
        executeAnalysis(text: text, completion: completion)
    }

    /// 실제 API 분석 실행
    private func executeAnalysis(text: String, completion: @escaping (Result<[TodoItem], Error>) -> Void) {
        // API URL 생성 (API 키를 쿼리 파라미터로 추가)
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            finishRequest(with: .failure(GeminiError.invalidURL), completion: completion)
            return
        }

        // 프롬프트 작성: AI에게 무엇을 해야 하는지 지시
        let prompt = createPrompt(for: text)

        // API 요청 바디 생성
        let requestBody = GeminiRequest(
            contents: [
                GeminiContent(
                    parts: [
                        GeminiPart(text: prompt)
                    ]
                )
            ],
            // 생성 설정 (비용 최적화)
            generationConfig: GenerationConfig(
                temperature: 0.1,      // 낮은 창의성 = 일관된 JSON 출력
                topK: 20,              // 후보 수 감소
                topP: 0.8,             // 더 엄격한 확률 분포
                maxOutputTokens: 2048  // 복수 일정 JSON 배열 대응
            )
        )

        // HTTP 요청 생성
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // iOS 앱 제한이 걸린 API 키 인증을 위해 번들 ID 헤더 필수
        if let bundleId = Bundle.main.bundleIdentifier {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        request.timeoutInterval = 60  // 타임아웃 60초로 증가

        // 요청 바디를 JSON으로 인코딩
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            finishRequest(with: .failure(error), completion: completion)
            return
        }

        // 재시도 포함 API 호출
        executeWithRetry(request: request, attempt: 1, completion: completion)
    }

    /// 요청 완료 처리 및 대기 큐 처리
    private func finishRequest(with result: Result<[TodoItem], Error>, completion: @escaping (Result<[TodoItem], Error>) -> Void) {
        DispatchQueue.main.async {
            self.isRequestInProgress = false
            completion(result)

            // 대기 중인 요청이 있으면 다음 요청 처리
            if !self.pendingRequests.isEmpty {
                let (nextText, nextCompletion) = self.pendingRequests.removeFirst()
                #if DEBUG
                print("📋 대기열에서 다음 요청 처리")
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + self.minCallInterval) {
                    self.analyzeTasks(text: nextText, completion: nextCompletion)
                }
            }
        }
    }

    /// API 호출 + 429/5xx 에러 시 자동 재시도 (지수 백오프)
    private func executeWithRetry(
        request: URLRequest,
        attempt: Int,
        completion: @escaping (Result<[TodoItem], Error>) -> Void
    ) {
        #if DEBUG
        print("🔄 API 호출 시도 \(attempt)/\(maxRetries)")
        #endif

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // 네트워크 에러 체크
            if let error = error {
                #if DEBUG
                print("❌ Gemini 네트워크 에러 (시도 \(attempt)): \(error)")
                GeminiService.writeDebugLog("❌ 네트워크 에러(시도\(attempt)): \(error.localizedDescription)")
                #endif
                if attempt < self.maxRetries {
                    let delay: Double = Double(attempt * 5)  // 5초, 10초, 15초...
                    #if DEBUG
                    print("⏳ 네트워크 에러 - \(delay)초 후 재시도...")
                    #endif
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.executeWithRetry(request: request, attempt: attempt + 1, completion: completion)
                    }
                    return
                }
                self.finishRequest(with: .failure(error), completion: completion)
                return
            }

            // HTTP 상태 코드 체크
            if let httpResponse = response as? HTTPURLResponse {
                #if DEBUG
                print("📡 Gemini API 응답 코드: \(httpResponse.statusCode) (시도 \(attempt)/\(self.maxRetries))")
                #endif

                // 429(요청 한도 초과) → 쿨다운 설정 후 재시도
                if httpResponse.statusCode == 429 {
                    // 60초 쿨다운 설정
                    self.rateLimitHitTime = Date()
                    self.rateLimitCooldown = 60

                    if attempt < 3 {
                        let delay: Double = 60  // 60초 대기
                        #if DEBUG
                        print("⚠️ Gemini API 요청 한도 초과 (429) - \(Int(delay))초 후 재시도...")
                        #endif
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                            self.executeWithRetry(request: request, attempt: attempt + 1, completion: completion)
                        }
                        return
                    }
                    #if DEBUG
                    print("⚠️ Gemini API 요청 한도 초과 (429) - 최대 재시도 실패")
                    #endif
                    self.finishRequest(with: .failure(GeminiError.rateLimited), completion: completion)
                    return
                }

                // 5xx(서버 에러) → 재시도
                if httpResponse.statusCode >= 500 {
                    if attempt < self.maxRetries {
                        let delay: Double = Double([5, 10, 20, 30, 60][min(attempt - 1, 4)])
                        #if DEBUG
                        print("⏳ 서버 에러 - \(Int(delay))초 후 재시도... (\(attempt)/\(self.maxRetries))")
                        #endif
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                            self.executeWithRetry(request: request, attempt: attempt + 1, completion: completion)
                        }
                        return
                    }
                    let errorBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "응답 없음"
                    #if DEBUG
                    print("❌ Gemini API 최대 재시도 초과: \(errorBody)")
                    #endif
                    self.finishRequest(with: .failure(GeminiError.apiError(httpResponse.statusCode)), completion: completion)
                    return
                }

                if httpResponse.statusCode != 200 {
                    let errorBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "응답 없음"
                    #if DEBUG
                    print("❌ Gemini API 에러: \(errorBody)")
                    GeminiService.writeDebugLog("❌ API 에러 \(httpResponse.statusCode):\n\(errorBody)")
                    #endif
                    self.finishRequest(with: .failure(GeminiError.apiError(httpResponse.statusCode)), completion: completion)
                    return
                }
            }

            // 데이터 체크
            guard let data = data else {
                self.finishRequest(with: .failure(GeminiError.noData), completion: completion)
                return
            }

            // 응답 파싱
            do {
                let response = try JSONDecoder().decode(GeminiResponse.self, from: data)

                // AI 응답에서 텍스트 추출
                guard let text = response.candidates?.first?.content?.parts?.first?.text else {
                    self.finishRequest(with: .failure(GeminiError.noContent), completion: completion)
                    return
                }

                // 디버깅용: Gemini 원본 응답을 파일에 저장 (개발 빌드 전용)
                #if DEBUG
                GeminiService.writeDebugLog("Gemini 응답 성공:\n\(text)")
                print("📄 Gemini 원본 응답:\n\(text)")
                #endif

                // JSON 응답을 TodoItem 배열로 변환
                let todoItems = self.parseTodoItems(from: text)
                #if DEBUG
                print("✅ Gemini 분석 성공: \(todoItems.count)개 할 일 추출")
                for (i, t) in todoItems.enumerated() {
                    print("   [\(i+1)] \(t.title) — \(t.suggestedHour ?? -1):\(t.suggestedMinute)")
                }
                #endif

                // 토큰 사용량 기록 (응답 텍스트 길이 기반 추정)
                let estimatedTokens = 200 + (text.count / 4)  // 프롬프트 + 응답
                APIUsageGuard.shared.recordTokenUsage(estimatedTokens)

                self.finishRequest(with: .success(todoItems), completion: completion)

            } catch {
                // 디버깅용: 원본 응답 출력
                if let responseString = String(data: data, encoding: .utf8) {
                    #if DEBUG
                    print("Gemini 응답: \(responseString)")
                    #endif
                }
                self.finishRequest(with: .failure(error), completion: completion)
            }
        }.resume()
    }

    // --------------------------------------------------------
    // MARK: - 프롬프트 생성 (비용 최적화)
    // --------------------------------------------------------
    // 토큰 사용량 최적화:
    // - 기존 프롬프트: ~800 토큰 → 최적화: ~200 토큰 (75% 감소)
    // - 불필요한 설명 제거, 압축된 형식 사용
    // - description/keywords 필드 선택적으로 변경
    // - maxOutputTokens: 2048 (복수 일정 JSON 배열 대응)
    // --------------------------------------------------------

    /// AI에게 전달할 프롬프트(지시문)를 생성합니다 - 토큰 최적화 버전
    private func createPrompt(for text: String) -> String {
        let language = LocalizationManager.shared.languageNameForAI

        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now) // 1=Sun, 2=Mon, ...

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d(E)"
        dateFormatter.locale = Locale(identifier: "en")
        let today = dateFormatter.string(from: now)

        // 현재 시간 (시:분)
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        // 간단한 요일 오프셋 (Sun=1부터)
        let wkOff = "Su:\((8-weekday)%7),Mo:\((9-weekday)%7),Tu:\((10-weekday)%7),We:\((11-weekday)%7),Th:\((12-weekday)%7),Fr:\((13-weekday)%7),Sa:\((14-weekday)%7)"

        return """
        You are a smart schedule assistant. Extract ALL tasks with INTELLIGENT inference.
        Reply with task titles in \(language). JSON keys and values for priority/recurrence MUST be in English.
        JSON array only, no markdown.
        IMPORTANT: If user mentions MULTIPLE tasks/events, return ALL of them as separate items in the array.

        ## CRITICAL: "title" field must contain ONLY the task/activity (2-10 words max)
        STRIP ALL date/time/recurrence words from the title. Keep only the core action or subject.
        The date, time, and recurrence belong in their own fields — NEVER in the title.

        Words that MUST be removed from title:
        - Dates: 오늘/내일/모레/글피/다음주/이번주/다음달, today/tomorrow, 月/火/水/木/金/土/日
        - Weekdays: 월요일~일요일, monday~sunday
        - Times: 아침/점심/저녁/야식/새벽/밤, morning/afternoon/evening/night
        - Specific times: "오전 9시", "오후 3시 10분", "8시 30분", "14:25", "3 PM", "반"
        - Recurrence: 매일/매주/매월/매년, every day/week/month/year, daily/weekly/monthly
        - Korean particles: "에", "에서", "부터", "까지" (at end of stripped phrase)
        - Filler: "할 일", "하기" (suffix, only when trivial)

        Title extraction examples (all 9 supported languages):
        ## Korean (한국어)
        - "내일 아침 8시 30분에 운동" → title: "운동"
        - "매주 월요일 오전 10시 팀 회의" → title: "팀 회의"
        - "오늘 오후 3시 회의하고 저녁 7시 운동" → [title:"회의", title:"운동"]

        ## English
        - "tomorrow 9am meeting with John" → title: "Meeting with John"
        - "every Monday at 10 team standup" → title: "Team standup"
        - "3 PM workout today" → title: "Workout"

        ## Japanese (日本語)
        - "明日の朝8時30分に運動" → title: "運動"
        - "毎週月曜日午前10時チーム会議" → title: "チーム会議"
        - "来週水曜日午後3時病院" → title: "病院"

        ## Chinese (中文)
        - "明天早上8点30分运动" → title: "运动"
        - "每周一上午10点团队会议" → title: "团队会议"
        - "下午3点去医院" → title: "医院"

        ## Spanish (Español)
        - "mañana a las 8:30 de la mañana ejercicio" → title: "Ejercicio"
        - "cada lunes a las 10 reunión de equipo" → title: "Reunión de equipo"
        - "hoy a las 3 de la tarde médico" → title: "Médico"

        ## Portuguese (Português)
        - "amanhã às 8:30 da manhã exercício" → title: "Exercício"
        - "toda segunda-feira às 10 reunião da equipe" → title: "Reunião da equipe"
        - "hoje às 15 horas médico" → title: "Médico"

        ## French (Français)
        - "demain à 8h30 entraînement" → title: "Entraînement"
        - "chaque lundi à 10h réunion d'équipe" → title: "Réunion d'équipe"
        - "aujourd'hui à 15h médecin" → title: "Médecin"

        ## Hindi (हिन्दी)
        - "कल सुबह 8:30 बजे व्यायाम" → title: "व्यायाम"
        - "हर सोमवार 10 बजे टीम मीटिंग" → title: "टीम मीटिंग"

        Rule of thumb: Strip ALL date/time/weekday/recurrence words and language-specific particles
        (조사/助詞/介词/partículas/prépositions). What remains is the title.
        If result is empty or too short, use the most meaningful noun/verb phrase.

        TODAY: \(today), CURRENT TIME: \(String(format: "%02d", currentHour)):\(String(format: "%02d", currentMinute)) (24-hour format)
        Weekday offsets from today (0=today): \(wkOff)
        User input: "\(text)"

        ## CRITICAL: suggestedHour MUST use 24-hour format (0-23)
        - 오전 1시/1 AM → suggestedHour: 1
        - 오전 9시/9 AM → suggestedHour: 9
        - 오후 1시/1 PM → suggestedHour: 13
        - 오후 3시/3 PM → suggestedHour: 15
        - 오후 6시/6 PM → suggestedHour: 18
        - 오후 9시/9 PM → suggestedHour: 21
        - 자정/midnight → suggestedHour: 0
        - 정오/noon → suggestedHour: 12
        NEVER return 1-12 for PM times. "오후 3시" = 15, NOT 3.

        ## CRITICAL: suggestedMinute MUST be extracted precisely (0-59)
        Parse minutes with 5-minute granularity or exact value. Do NOT default to 0 if a minute is mentioned.
        - "3시 10분" → hour:3, minute:10
        - "오후 3시 10분" → hour:15, minute:10
        - "오후 3시 반/half past 3 PM/3時半" → hour:15, minute:30
        - "오전 9시 45분" → hour:9, minute:45
        - "14:25" → hour:14, minute:25
        - "오후 2시 5분" → hour:14, minute:5
        - "2:30 PM" → hour:14, minute:30
        - "7시 15분 전/quarter to 7" → hour:6, minute:45
        - "7시 15분" → hour:7, minute:15
        - No minute mentioned → minute:0
        NEVER ignore the 분/minute value. "3시 10분" must NOT become minute:0.

        ## CRITICAL: Smart Date Logic Based on Current Time
        If user mentions a time that has ALREADY PASSED today → schedule for TOMORROW (daysFromToday: 1)

        Examples when current time is \(currentHour):00:
        - If now is 22:00 and user says "점심 약속" → daysFromToday: 1 (tomorrow lunch)
        - If now is 23:00 and user says "아침 운동" → daysFromToday: 1 (tomorrow morning)
        - If now is 20:00 and user says "저녁 식사" → daysFromToday: 0 if 19:00 is still reasonable, else 1
        - If now is 14:00 and user says "오전 회의" → daysFromToday: 1 (tomorrow morning)

        Rule: If inferred hour < current hour - 2, assume TOMORROW unless user explicitly says "오늘"

        ## CRITICAL: Use Common Sense for Time Inference (hour 0-23)
        Think like a real person. Infer the MOST NATURAL time based on daily life patterns:

        ### Meals - When do people actually eat?
        - 아침/朝食/breakfast → 7:30-8:00 (before work)
        - 점심/昼食/lunch → 12:00-12:30 (lunch break)
        - 저녁/夕食/dinner → 19:00-19:30 (after work, relaxed)
        - 야식/late snack → 22:00

        ### Work - Typical office hours
        - 출근/commute → 8:30 (arrive at 9)
        - 오전 회의/morning meeting → 10:00
        - 오후 회의/afternoon meeting → 14:00-15:00
        - 퇴근/leave work → 18:00
        - 야근/overtime → 20:00-21:00

        ### Exercise - When do people work out?
        - 아침 운동/morning workout → 7:00 (before work)
        - 운동/gym/헬스 → 19:00 (after work, most common)
        - 러닝/조깅/running → 7:00 or 19:00
        - 요가/yoga → 7:00 or 20:00

        ### Social - Natural meeting times
        - 점심 약속/lunch meeting → 12:00
        - 저녁 약속/dinner appointment → 19:00
        - 카페/coffee → 14:00-15:00 (afternoon break)
        - 술/drinks/회식 → 19:00-20:00
        - 데이트/date → 18:30-19:00

        ### Daily Life
        - 기상/wake up → 7:00
        - 병원/hospital/clinic → 10:00 (morning appointment)
        - 은행/bank → 10:00-14:00
        - 장보기/grocery shopping → 18:30 (after work)
        - 집안일/housework/청소 → 10:00 (weekend) or 20:00 (weekday)
        - 취침/sleep → 23:00

        ### If no clear time hint → Default to 9:00 (start of day)

        ## Priority Inference
        - HIGH: urgent/긴급/緊急/deadline/마감/회의/meeting/important/중요
        - MEDIUM: normal tasks, appointments, regular activities
        - LOW: 나중에/later/sometime/여유/maybe/언젠가

        ## Duration Inference (minutes)
        - Quick tasks (call, message): 5-15
        - Meals: 30-60
        - Meetings: 60-120
        - Exercise: 60-90
        - Shopping: 60-120
        - Default: 30

        ## CRITICAL: Date Inference (daysFromToday field)
        MUST correctly set daysFromToday based on date keywords:
        - 오늘/today/今日/hoy/hoje → daysFromToday: 0
        - 내일/tomorrow/明日/mañana/amanhã → daysFromToday: 1
        - 모레/day after tomorrow/明後日 → daysFromToday: 2
        - 이번주 [요일]/this week → use WkOffset
        - 다음주/next week/来週 → add 7 to WkOffset
        - If no date mentioned AND inferred time has NOT passed → daysFromToday: 0
        - If no date mentioned AND inferred time HAS passed (hour < currentHour - 2) → daysFromToday: 1

        IMPORTANT: "내일 저녁" = daysFromToday:1, "tomorrow morning" = daysFromToday:1

        ## Recurrence (MUST detect ALL recurrence keywords)
        - 매일/daily/every day/毎日/每天/diario → "daily"
        - 매주/weekly/every week/毎週/每周/semanal → "weekly"
        - 매월/매달/monthly/every month/毎月/每月/mensual → "monthly"
        - 매년/yearly/annually/every year/毎年/每年 → "yearly"
        - Default: "none"
        IMPORTANT: "매주 월요일" → recurrence:"weekly", daysFromToday: offset to next Monday
        IMPORTANT: "매일 아침 운동" → recurrence:"daily", daysFromToday:0, suggestedHour:7

        ## Multi-Task Extraction (CRITICAL — MOST IMPORTANT RULE)
        User may mention MULTIPLE tasks in one sentence. NEVER merge them into a single task.
        Split by these connectors (Korean/English/Japanese/Chinese):
        - Commas: ",", "、", "，", ";"
        - Korean: "그리고", "하고", "랑", "과", "그 다음", "다음으로", "그담에"
        - English: " and ", ", then ", " then "
        - Japanese: "それから", "それと"
        - Chinese: "然后", "然後"

        Each task → separate JSON object in the array.

        ### Vague task words still count as tasks
        Even if the user uses vague words like "일정/event/schedule/予定/事情",
        each one with a distinct time is a SEPARATE task. Preserve them all.
        - "8시 기상, 9시 일정, 10시 일정" → 3 tasks, NOT 1
          → [{"title":"기상","suggestedHour":8,...},
              {"title":"일정","suggestedHour":9,...},
              {"title":"일정","suggestedHour":10,...}]
        - When title is vague, use the Korean word "일정" or English "Event" or the user's original word.
        - NEVER drop a task just because its description is vague — the time specificity is enough.

        Example: "내일 오후 3시 회의하고 저녁 7시 운동" →
        [{"title":"회의",...,"suggestedHour":15,"suggestedMinute":0,"daysFromToday":1},
         {"title":"운동",...,"suggestedHour":19,"suggestedMinute":0,"daysFromToday":1}]

        Example: "8시 기상하고 9시 10분 일정 그리고 10시 일정" →
        [{"title":"기상","suggestedHour":8,"suggestedMinute":0,...},
         {"title":"일정","suggestedHour":9,"suggestedMinute":10,...},
         {"title":"일정","suggestedHour":10,"suggestedMinute":0,...}]

        COUNT THE DISTINCT TIMES: if user mentions N different times, output N tasks.

        Output format (JSON array only, suggestedHour: 0-23, suggestedMinute: 0-59):
        [{"title":"task name","priority":"high/medium/low","estimatedDuration":30,"suggestedHour":14,"suggestedMinute":0,"daysFromToday":0,"recurrence":"none"}]

        ## Worked Examples
        - "내일 오후 3시 10분에 운동" → suggestedHour:15, suggestedMinute:10, daysFromToday:1, recurrence:"none"
        - "매주 월요일 오전 9시 팀 회의" → suggestedHour:9, suggestedMinute:0, recurrence:"weekly", daysFromToday: offset to Monday
        - "매일 아침 7시 30분 러닝" → suggestedHour:7, suggestedMinute:30, recurrence:"daily", daysFromToday:0
        - "오늘 14:25 알람" → suggestedHour:14, suggestedMinute:25, daysFromToday:0
        - "내일 3시 반 카페" → suggestedHour:15, suggestedMinute:30 (3시 반 with 카페 context → PM), daysFromToday:1
        """
    }

    // --------------------------------------------------------
    // MARK: - 폴백 파서 (AI 실패 시 로컬 파싱)
    // --------------------------------------------------------

    /// AI 없이 규칙 기반으로 할 일을 추출합니다 (Gemini 프롬프트 상식 규칙 반영)
    /// 복수 일정 입력 시 쉼표/그리고/하고 등으로 분할 후 각각 개별 TodoItem 생성
    func fallbackParse(text: String) -> [TodoItem] {
        #if DEBUG
        print("🔄 폴백 파서 사용: \(text)")
        #endif

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 복수 일정 분할 시도
        let segments = splitIntoTaskSegments(trimmed)

        #if DEBUG
        if segments.count > 1 {
            print("✂️ 복수 일정 감지: \(segments.count)개 분할")
            for (i, seg) in segments.enumerated() { print("   [\(i+1)] \(seg)") }
        }
        #endif

        // 각 조각을 개별 TodoItem으로 파싱
        var results: [TodoItem] = []
        for segment in segments {
            let items = parseSingleSegment(text: segment)
            results.append(contentsOf: items)
        }
        return results
    }

    /// 입력 문장을 복수 일정 조각으로 분할한다.
    /// 분할 기준: 쉼표(, 、，), "그리고", "그리고는", "하고", "랑", "과", "; 그리고", " and ", " then "
    /// 단, 숫자 사이 쉼표(예: "1,000")나 짧은 조각은 합친다.
    private func splitIntoTaskSegments(_ text: String) -> [String] {
        // 연결어를 공통 구분자(|||)로 치환 후 분리 (9개 언어 지원)
        var t = text
        let connectors: [String] = [
            // ── 한국어 ── (긴 것 먼저, 치환 순서 중요)
            "하고 난 다음에", "하고 난 다음", "하고 난 뒤에", "하고 난 뒤",
            "한 다음에", "한 다음", "한 뒤에", "한 뒤",
            "간 다음에", "간 다음", "간다음",
            "그러고 나서", "그리고 나서", "그리고는", "그리고",
            "그 다음에", "그다음에", "그 다음", "그다음", "그담에", "다음으로", "이어서",
            " 하고 ", "하고서 ", " 하고서", " 한 뒤 ", " 한 후 ",

            // ── 영어 ── (소문자 치환, caseInsensitive)
            " and then ", ", then ", " then ", " and ", " followed by ", " after that ",
            " next ", " afterwards ", " subsequently ",

            // ── 일본어 ── (接続詞)
            "それから", "それと", "その後", "そして", "次に", "続いて", "そのあとで", "そのあと",

            // ── 중국어 간체/번체 ──
            "然后", "然後", "接着", "接著", "之后", "之後", "再来", "再來", "跟着", "跟著",

            // ── 스페인어 ──
            " y después ", " y luego ", " luego ", " después ", " y ", " entonces ",

            // ── 포르투갈어 ──
            " e depois ", " e então ", " depois ", " então ", " e ",

            // ── 프랑스어 ──
            " et puis ", " puis ", " ensuite ", " et ", " après cela ", " après ",

            // ── 힌디어 ──
            " फिर ", " उसके बाद ", " और फिर ", " और ", " बाद में ",
        ]
        for c in connectors {
            t = t.replacingOccurrences(of: c, with: "|||", options: .caseInsensitive)
        }

        // 쉼표 종류 전부 분리자로
        for comma in [",", "，", "、", ";", "；"] {
            t = t.replacingOccurrences(of: comma, with: "|||")
        }

        // 조각으로 분할 + 공백 정리
        var segments = t.components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 너무 짧은 조각(숫자/단어 2글자 이하)은 앞 조각에 합친다 (예: "1,000" 오분할 방지)
        var merged: [String] = []
        for seg in segments {
            if seg.count <= 2, let last = merged.popLast() {
                merged.append(last + " " + seg)
            } else {
                merged.append(seg)
            }
        }
        segments = merged

        // 분할 결과가 1개 이하면 원문 그대로 반환 (쪼갤 게 없음)
        if segments.count <= 1 { return [text] }
        return segments
    }

    /// 단일 조각 텍스트를 1개의 TodoItem으로 파싱 (기존 로직)
    private func parseSingleSegment(text: String) -> [TodoItem] {
        // 빈 텍스트 체크
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())

        // 우선순위 키워드
        let highPriorityKeywords = ["중요", "급한", "긴급", "urgent", "important", "asap", "마감", "deadline", "회의", "meeting"]
        let lowPriorityKeywords = ["나중에", "여유", "언젠가", "later", "sometime", "maybe"]

        // ── 시간 파싱 (AM/PM + 분 정확 처리) ──
        var suggestedHour: Int? = nil
        var suggestedMinute: Int = 0

        // 헬퍼: 정규식 매치 → (hour, minute?) 추출
        func firstMatch(_ pattern: String, in str: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            let range = NSRange(str.startIndex..., in: str)
            guard let m = regex.firstMatch(in: str, range: range) else { return nil }
            var groups: [String] = []
            for i in 1..<m.numberOfRanges {
                if let r = Range(m.range(at: i), in: str) {
                    groups.append(String(str[r]))
                } else {
                    groups.append("")
                }
            }
            return groups
        }

        // 시:분 동시 추출 패턴 (우선순위 높음)
        // 1) 오전/오후 + 시 + 분
        if let g = firstMatch("오전\\s*(\\d{1,2})\\s*시\\s*(\\d{1,2})\\s*분", in: text),
           let h = Int(g[0]), let m = Int(g[1]) {
            suggestedHour = (h == 12 ? 0 : h)
            suggestedMinute = m
        } else if let g = firstMatch("오후\\s*(\\d{1,2})\\s*시\\s*(\\d{1,2})\\s*분", in: text),
                  let h = Int(g[0]), let m = Int(g[1]) {
            suggestedHour = (h == 12 ? 12 : h + 12)
            suggestedMinute = m
        }
        // 2) 오전/오후 + 시 + 반 (30분)
        else if let g = firstMatch("오전\\s*(\\d{1,2})\\s*시\\s*반", in: text), let h = Int(g[0]) {
            suggestedHour = (h == 12 ? 0 : h); suggestedMinute = 30
        } else if let g = firstMatch("오후\\s*(\\d{1,2})\\s*시\\s*반", in: text), let h = Int(g[0]) {
            suggestedHour = (h == 12 ? 12 : h + 12); suggestedMinute = 30
        }
        // 3) 오전/오후 + 시 (분 없음)
        else if let g = firstMatch("오전\\s*(\\d{1,2})\\s*시", in: text), let h = Int(g[0]) {
            suggestedHour = (h == 12 ? 0 : h)
        } else if let g = firstMatch("오후\\s*(\\d{1,2})\\s*시", in: text), let h = Int(g[0]) {
            suggestedHour = (h == 12 ? 12 : h + 12)
        }
        // 4) HH:MM 24시간 표기
        else if let g = firstMatch("(\\d{1,2}):(\\d{2})", in: text),
                let h = Int(g[0]), let m = Int(g[1]) {
            suggestedHour = h; suggestedMinute = m
        }
        // 5) N am/pm + 분
        else if let g = firstMatch("(\\d{1,2})\\s*(?::|시)?\\s*(\\d{1,2})?\\s*am", in: text), let h = Int(g[0]) {
            suggestedHour = (h == 12 ? 0 : h)
            if g.count > 1, let m = Int(g[1]) { suggestedMinute = m }
        } else if let g = firstMatch("(\\d{1,2})\\s*(?::|시)?\\s*(\\d{1,2})?\\s*pm", in: text), let h = Int(g[0]) {
            suggestedHour = (h == 12 ? 12 : h + 12)
            if g.count > 1, let m = Int(g[1]) { suggestedMinute = m }
        }
        // 6) N시 M분 (오전/오후 미지정)
        else if let g = firstMatch("(\\d{1,2})\\s*시\\s*(\\d{1,2})\\s*분", in: text),
                let h = Int(g[0]), let m = Int(g[1]) {
            suggestedHour = (h >= 1 && h <= 6) ? h + 12 : h
            suggestedMinute = m
        }
        // 7) N시 반
        else if let g = firstMatch("(\\d{1,2})\\s*시\\s*반", in: text), let h = Int(g[0]) {
            suggestedHour = (h >= 1 && h <= 6) ? h + 12 : h
            suggestedMinute = 30
        }
        // 8) N시 단독
        else if let g = firstMatch("(\\d{1,2})\\s*시", in: text), let h = Int(g[0]) {
            suggestedHour = (h >= 1 && h <= 6) ? h + 12 : h
        }

        // 경계값 보정
        if let h = suggestedHour { suggestedHour = max(0, min(23, h)) }
        suggestedMinute = max(0, min(59, suggestedMinute))

        // ── 활동 기반 상식 시간 추론 (명시 시간 없을 때) ──
        var estimatedDuration = 60
        if suggestedHour == nil {
            let t = text.lowercased()
            if t.contains("아침") || t.contains("breakfast") || t.contains("朝") {
                suggestedHour = 8; estimatedDuration = 30
            } else if t.contains("점심") || t.contains("lunch") || t.contains("昼") {
                suggestedHour = 12; estimatedDuration = 60
            } else if t.contains("저녁") || t.contains("dinner") || t.contains("夕") {
                suggestedHour = 19; estimatedDuration = 60
            } else if t.contains("야식") || t.contains("late snack") {
                suggestedHour = 22; estimatedDuration = 30
            } else if t.contains("출근") || t.contains("commute") {
                suggestedHour = 9; estimatedDuration = 30
            } else if t.contains("퇴근") || t.contains("leave work") {
                suggestedHour = 18; estimatedDuration = 30
            } else if t.contains("운동") || t.contains("gym") || t.contains("헬스") || t.contains("exercise") {
                suggestedHour = 19; estimatedDuration = 90
            } else if t.contains("러닝") || t.contains("조깅") || t.contains("running") {
                suggestedHour = 7; estimatedDuration = 60
            } else if t.contains("요가") || t.contains("yoga") {
                suggestedHour = 7; estimatedDuration = 60
            } else if t.contains("카페") || t.contains("coffee") || t.contains("커피") {
                suggestedHour = 15; estimatedDuration = 60
            } else if t.contains("술") || t.contains("회식") || t.contains("drinks") {
                suggestedHour = 19; estimatedDuration = 120
            } else if t.contains("병원") || t.contains("hospital") || t.contains("치과") {
                suggestedHour = 10; estimatedDuration = 60
            } else if t.contains("장보기") || t.contains("마트") || t.contains("grocery") {
                suggestedHour = 19; estimatedDuration = 60
            } else if t.contains("회의") || t.contains("meeting") || t.contains("미팅") {
                suggestedHour = 10; estimatedDuration = 60
            }
        }

        // 최종 기본값
        if suggestedHour == nil { suggestedHour = 9 }

        // ── 날짜 파싱 ──
        var daysFromToday = 0
        var hasExplicitDate = false
        let lowerT = text.lowercased()
        let isNextWeek = text.contains("다음주") || lowerT.contains("next week")

        if text.contains("내일") || lowerT.contains("tomorrow") {
            daysFromToday = 1; hasExplicitDate = true
        } else if text.contains("모레") || lowerT.contains("day after") {
            daysFromToday = 2; hasExplicitDate = true
        } else if text.contains("글피") {
            daysFromToday = 3; hasExplicitDate = true
        } else if text.contains("오늘") || lowerT.contains("today") {
            daysFromToday = 0; hasExplicitDate = true
        } else if isNextWeek {
            daysFromToday = 7; hasExplicitDate = true  // 요일 미지정 시 다음주 오늘
        }

        // 요일 파싱 (다음주 오프셋과 올바르게 결합)
        let weekdays = [
            ("월요일", "monday", 2), ("화요일", "tuesday", 3), ("수요일", "wednesday", 4),
            ("목요일", "thursday", 5), ("금요일", "friday", 6), ("토요일", "saturday", 7), ("일요일", "sunday", 1)
        ]
        let currentWeekday = calendar.component(.weekday, from: Date())

        for (ko, en, target) in weekdays {
            if text.contains(ko) || lowerT.contains(en) {
                var diff = target - currentWeekday
                if diff <= 0 { diff += 7 }          // 이번 주의 해당 요일 (지났으면 다음 주)
                if isNextWeek { diff += 7 }          // "다음주 월요일" → 다음 주로 이동
                daysFromToday = diff
                hasExplicitDate = true
                break
            }
        }

        // ── 과거 시간 → 내일 자동 전환 ──
        if !hasExplicitDate, let hour = suggestedHour, hour < currentHour - 2 {
            daysFromToday = 1
        }

        // ── 반복 파싱 ──
        var recurrence: Recurrence = .none
        if text.contains("매일") || lowerT.contains("every day") || lowerT.contains("daily") {
            recurrence = .daily
        } else if text.contains("매주") || lowerT.contains("every week") || lowerT.contains("weekly") {
            recurrence = .weekly
        } else if text.contains("매월") || text.contains("매달") || lowerT.contains("every month") || lowerT.contains("monthly") {
            recurrence = .monthly
        } else if text.contains("매년") || text.contains("매해") || lowerT.contains("every year") || lowerT.contains("yearly") || lowerT.contains("annually") {
            recurrence = .yearly
        }

        // ── 우선순위 결정 ──
        var priority: Priority = .medium
        let lowerText = text.lowercased()
        for keyword in highPriorityKeywords {
            if lowerText.contains(keyword) { priority = .high; break }
        }
        if priority == .medium {
            for keyword in lowPriorityKeywords {
                if lowerText.contains(keyword) { priority = .low; break }
            }
        }

        // ── 제목 생성 (날짜/시간/조사 제거) ──
        var title = cleanTitle(from: text)
        if title.isEmpty { title = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if title.count > 50 { title = String(title.prefix(50)) + "..." }
        if let first = title.first { title = first.uppercased() + title.dropFirst() }

        let todayStart = calendar.startOfDay(for: Date())
        let scheduledDate = calendar.date(byAdding: .day, value: daysFromToday, to: todayStart) ?? todayStart

        let todoItem = TodoItem(
            title: title,
            description: "",
            priority: priority,
            estimatedDuration: estimatedDuration,
            suggestedHour: suggestedHour,
            suggestedMinute: suggestedMinute,
            scheduledDate: scheduledDate,
            recurrence: recurrence,
            keywords: []
        )

        return [todoItem]
    }

    // --------------------------------------------------------
    // MARK: - 제목 정제 (날짜/시간/조사 제거)
    // --------------------------------------------------------

    /// 입력 문장에서 날짜, 시간, 반복 키워드, 조사를 제거하여 순수 작업 제목만 남긴다.
    /// 9개 언어 지원: 한국어/영어/일본어/중국어(간/번)/스페인어/포르투갈어/프랑스어/힌디어
    /// 예) "내일 아침 8시 30분에 운동" → "운동"
    ///     "매주 월요일 오전 10시 팀 회의" → "팀 회의"
    ///     "明日の朝8時30分に運動" → "運動"
    ///     "tomorrow 8:30am workout" → "workout"
    private func cleanTitle(from text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // ─────────────────────────────────────────────
        // 1) 정규식으로 시간 표현 제거 (순서 중요: 긴 패턴 먼저)
        // ─────────────────────────────────────────────
        let regexPatterns: [String] = [
            // 한국어 시간 표현
            "오전\\s*\\d{1,2}\\s*시\\s*\\d{1,2}\\s*분",
            "오후\\s*\\d{1,2}\\s*시\\s*\\d{1,2}\\s*분",
            "오전\\s*\\d{1,2}\\s*시\\s*반",
            "오후\\s*\\d{1,2}\\s*시\\s*반",
            "오전\\s*\\d{1,2}\\s*시",
            "오후\\s*\\d{1,2}\\s*시",
            "\\d{1,2}\\s*시\\s*\\d{1,2}\\s*분",
            "\\d{1,2}\\s*시\\s*반",
            "\\d{1,2}\\s*시",

            // 일본어 시간 표현 (時/分/半)
            "午前\\s*\\d{1,2}\\s*時\\s*\\d{1,2}\\s*分",
            "午後\\s*\\d{1,2}\\s*時\\s*\\d{1,2}\\s*分",
            "午前\\s*\\d{1,2}\\s*時\\s*半",
            "午後\\s*\\d{1,2}\\s*時\\s*半",
            "午前\\s*\\d{1,2}\\s*時",
            "午後\\s*\\d{1,2}\\s*時",
            "\\d{1,2}\\s*時\\s*\\d{1,2}\\s*分",
            "\\d{1,2}\\s*時\\s*半",
            "\\d{1,2}\\s*時",

            // 중국어 시간 표현 (点/點/分/半)
            "上午\\s*\\d{1,2}\\s*[点點]\\s*\\d{1,2}\\s*分",
            "下午\\s*\\d{1,2}\\s*[点點]\\s*\\d{1,2}\\s*分",
            "晚上\\s*\\d{1,2}\\s*[点點]",
            "上午\\s*\\d{1,2}\\s*[点點]",
            "下午\\s*\\d{1,2}\\s*[点點]",
            "\\d{1,2}\\s*[点點]\\s*\\d{1,2}\\s*分",
            "\\d{1,2}\\s*[点點]\\s*半",
            "\\d{1,2}\\s*[点點]",

            // 스페인어 시간 표현 (a las N, de la mañana/tarde/noche)
            "a\\s+las\\s+\\d{1,2}(:\\d{2})?\\s*(de\\s+la\\s+(mañana|tarde|noche))?",
            "a\\s+la\\s+\\d{1,2}(:\\d{2})?\\s*(de\\s+la\\s+(mañana|tarde|noche))?",

            // 포르투갈어 시간 표현 (às N, da manhã/tarde/noite)
            "às\\s+\\d{1,2}(:\\d{2})?(\\s*(h|horas?))?\\s*(da\\s+(manhã|tarde|noite))?",
            "as\\s+\\d{1,2}(:\\d{2})?(\\s*(h|horas?))?",

            // 프랑스어 시간 표현 (à N heures)
            "à\\s+\\d{1,2}\\s*(heures?|h)(\\s*\\d{1,2})?",
            "\\d{1,2}\\s*h\\s*\\d{1,2}",
            "\\d{1,2}\\s*heures?(\\s+\\d{1,2})?",

            // 힌디어 시간 표현 (N बजे)
            "\\d{1,2}\\s*बजे\\s*\\d{1,2}?",

            // 공통: HH:MM, N am/pm, o'clock
            "\\d{1,2}:\\d{2}\\s*[ap]\\.?m\\.?",
            "\\d{1,2}:\\d{2}",
            "\\d{1,2}\\s*[ap]\\.?m\\.?",
            "\\d{1,2}\\s+o'?clock",
            "\\d{1,2}\\s*時",          // 단독 중국/일본어
            "\\d{1,2}\\s*点",
            "\\d{1,2}\\s*點",
        ]
        for pattern in regexPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(t.startIndex..., in: t)
                t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: " ")
            }
        }

        // ─────────────────────────────────────────────
        // 2) 키워드 단어 제거 (9개 언어)
        // ─────────────────────────────────────────────
        let wordsToRemove: [String] = [
            // ── 한국어 ko ──
            "오늘", "내일", "모레", "글피", "다음주", "다음 주", "이번주", "이번 주",
            "다음달", "이번달", "다음 달", "이번 달",
            "월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일",
            "아침", "점심", "저녁", "야식", "새벽", "밤", "낮", "오전", "오후",
            "매일", "매주", "매월", "매달", "매년", "매해",

            // ── 영어 en ──
            "today", "tomorrow", "yesterday", "day after tomorrow",
            "next week", "this week", "next month", "this month", "next year", "this year",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "mon", "tue", "wed", "thu", "fri", "sat", "sun",
            "morning", "afternoon", "evening", "night", "midnight", "noon", "dawn",
            "every day", "every week", "every month", "every year",
            "daily", "weekly", "monthly", "yearly", "annually",

            // ── 일본어 ja ──
            "今日", "明日", "明後日", "昨日",
            "来週", "今週", "来月", "今月", "来年", "今年",
            "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日", "日曜日",
            "月曜", "火曜", "水曜", "木曜", "金曜", "土曜", "日曜",
            "朝", "昼", "夕方", "夜", "午前", "午後", "正午", "深夜",
            "毎日", "毎週", "毎月", "毎年",

            // ── 중국어 간체/번체 zh ──
            "今天", "明天", "后天", "後天", "昨天",
            "下周", "下週", "这周", "這週", "下个月", "下個月", "这个月", "這個月",
            "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日", "星期天",
            "周一", "周二", "周三", "周四", "周五", "周六", "周日",
            "週一", "週二", "週三", "週四", "週五", "週六", "週日",
            "早上", "上午", "中午", "下午", "晚上", "夜晚", "清晨",
            "每天", "每周", "每週", "每月", "每年",

            // ── 스페인어 es ──
            "hoy", "mañana", "pasado mañana", "ayer",
            "próxima semana", "esta semana", "próximo mes", "este mes", "próximo año",
            "proxima semana", "proximo mes",  // 악센트 없는 변형
            "lunes", "martes", "miércoles", "miercoles", "jueves", "viernes", "sábado", "sabado", "domingo",
            "mañana", "tarde", "noche", "madrugada", "mediodía", "mediodia", "medianoche",
            "diario", "semanal", "mensual", "anual",
            "cada día", "cada semana", "cada mes", "cada año",
            "todos los días", "todas las semanas", "todos los meses",

            // ── 포르투갈어 pt-BR ──
            "hoje", "amanhã", "amanha", "depois de amanhã", "ontem",
            "próxima semana", "proxima semana", "esta semana",
            "próximo mês", "proximo mes", "este mês", "este mes",
            "segunda-feira", "terça-feira", "terca-feira", "quarta-feira", "quinta-feira",
            "sexta-feira", "sábado", "sabado", "domingo",
            "segunda", "terça", "terca", "quarta", "quinta", "sexta",
            "manhã", "manha", "tarde", "noite", "madrugada", "meio-dia", "meia-noite",
            "diário", "diario", "semanal", "mensal", "anual",
            "todo dia", "toda semana", "todo mês", "todo mes", "todo ano",

            // ── 프랑스어 fr ──
            "aujourd'hui", "aujourdhui", "demain", "après-demain", "apres-demain", "hier",
            "semaine prochaine", "cette semaine", "mois prochain", "ce mois",
            "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
            "matin", "midi", "après-midi", "apres-midi", "soir", "nuit", "minuit",
            "quotidien", "hebdomadaire", "mensuel", "annuel",
            "tous les jours", "toutes les semaines", "tous les mois", "tous les ans",
            "chaque jour", "chaque semaine", "chaque mois", "chaque an",

            // ── 힌디어 hi ──
            "आज", "कल", "परसों", "परसो",
            "अगले सप्ताह", "इस सप्ताह", "अगले महीने", "इस महीने",
            "सोमवार", "मंगलवार", "बुधवार", "गुरुवार", "शुक्रवार", "शनिवार", "रविवार",
            "सुबह", "दोपहर", "शाम", "रात", "मध्यरात्रि",
            "रोज़", "रोज", "हर दिन", "हर हफ्ते", "हर महीने", "हर साल",
            "प्रतिदिन", "साप्ताहिक", "मासिक", "वार्षिक",
        ]

        // 긴 것부터 제거 (단어 충돌 방지)
        for word in wordsToRemove.sorted(by: { $0.count > $1.count }) {
            t = t.replacingOccurrences(of: word, with: " ", options: [.caseInsensitive])
        }

        // ─────────────────────────────────────────────
        // 3) 조사/전치사 제거 (언어별)
        // ─────────────────────────────────────────────
        let particlePatterns: [String] = [
            // 한국어 조사
            "에\\s", "에서\\s", "부터\\s", "까지\\s", "에$", "에서$", "에게\\s", "께\\s",
            // 일본어 조사
            "に\\s", "で\\s", "から\\s", "まで\\s", "の\\s", "に$", "で$",
            // 중국어 介词 (在/到/从)
            "\\s在\\s", "\\s到\\s", "\\s从\\s", "\\s從\\s",
            // 영어/스페인어/포르투갈어/프랑스어 짧은 전치사 (단어 경계 필수)
            "\\bat\\b", "\\bon\\b", "\\bin\\b", "\\bfrom\\b", "\\bto\\b", "\\buntil\\b",
            "\\ba\\s+las?\\b", "\\bde\\s+la\\b", "\\bel\\b", "\\bla\\b",
            "\\bà\\b", "\\bau\\b", "\\baux\\b", "\\bde\\b", "\\bdu\\b",
            "\\bàs\\b", "\\bdas?\\b", "\\bdos?\\b",
            // 힌디어 को/से/तक/में
            "\\sको\\s", "\\sसे\\s", "\\sतक\\s", "\\sमें\\s",
        ]
        for pattern in particlePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(t.startIndex..., in: t)
                t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: " ")
            }
        }

        // ─────────────────────────────────────────────
        // 4) 연속 공백/구두점 정리
        // ─────────────────────────────────────────────
        if let regex = try? NSRegularExpression(pattern: "[,，、.。]+", options: []) {
            let range = NSRange(t.startIndex..., in: t)
            t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: " ")
        }
        if let regex = try? NSRegularExpression(pattern: "\\s+", options: []) {
            let range = NSRange(t.startIndex..., in: t)
            t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: " ")
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // --------------------------------------------------------
    // MARK: - 응답 파싱
    // --------------------------------------------------------

    /// AI 응답 텍스트에서 TodoItem 배열을 추출합니다
    private func parseTodoItems(from text: String) -> [TodoItem] {
        // JSON 부분만 추출 (```json ... ``` 사이)
        var jsonString = text

        // 마크다운 코드 블록 제거
        if let startRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", range: startRange.upperBound..<text.endIndex) {
            jsonString = String(text[startRange.upperBound..<endRange.lowerBound])
        } else if let startRange = text.range(of: "["),
                  let endRange = text.range(of: "]", options: .backwards) {
            // 대괄호로 둘러싸인 부분 추출
            jsonString = String(text[startRange.lowerBound...endRange.lowerBound])
        } else if let startRange = text.range(of: "[") {
            // ']'가 없는 경우 (토큰 제한으로 잘린 JSON 복구)
            var truncated = String(text[startRange.lowerBound...])
            // 마지막 완전한 객체까지만 유지
            if let lastCloseBrace = truncated.range(of: "}", options: .backwards) {
                var recovered = String(truncated[...lastCloseBrace.lowerBound])
                // trailing comma 제거 (잘린 JSON에서 발생)
                recovered = recovered.trimmingCharacters(in: .whitespaces)
                if recovered.hasSuffix(",") {
                    recovered = String(recovered.dropLast())
                }
                truncated = recovered + "]"
            } else {
                truncated += "]"
            }
            jsonString = truncated
            #if DEBUG
            print("⚠️ 잘린 JSON 복구 시도: \(jsonString.prefix(200))")
            #endif
        }

        // JSON 파싱
        guard let data = jsonString.data(using: .utf8) else {
            #if DEBUG
            print("JSON 문자열 변환 실패")
            #endif
            return []
        }

        do {
            // JSON을 딕셔너리 배열로 디코딩
            let rawItems = try JSONDecoder().decode([RawTodoItem].self, from: data)

            // RawTodoItem을 TodoItem으로 변환
            return rawItems.map { raw in
                // AI가 반환하는 영어 우선순위를 매핑
                let priority: Priority
                switch raw.priority.lowercased() {
                case "high": priority = .high
                case "medium": priority = .medium
                case "low": priority = .low
                default: priority = .medium
                }

                // 날짜 계산 (오늘 시작 + daysFromToday)
                let todayStart = Calendar.current.startOfDay(for: Date())
                let scheduledDate = Calendar.current.date(
                    byAdding: .day,
                    value: raw.daysFromToday ?? 0,
                    to: todayStart
                ) ?? todayStart

                // 반복 주기 매핑
                let recurrence: Recurrence
                switch raw.recurrence?.lowercased() {
                case "daily": recurrence = .daily
                case "weekly": recurrence = .weekly
                case "monthly": recurrence = .monthly
                case "yearly": recurrence = .yearly
                default: recurrence = .none
                }

                // 안전망: AI가 날짜/시간을 제목에 남겼을 수 있으니 한 번 더 정제
                var cleanedTitle = self.cleanTitle(from: raw.title)
                if cleanedTitle.isEmpty { cleanedTitle = raw.title }
                let capitalizedTitle = cleanedTitle.prefix(1).uppercased() + cleanedTitle.dropFirst()

                return TodoItem(
                    title: capitalizedTitle,
                    description: raw.description,
                    priority: priority,
                    estimatedDuration: max(5, min(480, raw.estimatedDuration ?? 60)),
                    suggestedHour: max(0, min(23, raw.suggestedHour ?? 9)),
                    suggestedMinute: max(0, min(59, raw.suggestedMinute ?? 0)),
                    scheduledDate: scheduledDate,
                    recurrence: recurrence,
                    keywords: raw.keywords ?? []
                )
            }
        } catch {
            #if DEBUG
            print("JSON 파싱 에러: \(error)")
            #endif
            return []
        }
    }
}

// ============================================================
// MARK: - API 요청/응답 모델들
// ============================================================

// Gemini API 요청 구조
struct GeminiRequest: Codable {
    let contents: [GeminiContent]
    let generationConfig: GenerationConfig?
}

struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    let text: String
}

struct GenerationConfig: Codable {
    let temperature: Double?
    let topK: Int?
    let topP: Double?
    let maxOutputTokens: Int?
}

// Gemini API 응답 구조
struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Codable {
    let content: GeminiResponseContent?
}

struct GeminiResponseContent: Codable {
    let parts: [GeminiPart]?
}

// AI가 반환하는 할 일 아이템 (최적화된 구조)
struct RawTodoItem: Codable {
    let title: String
    let description: String?      // 선택적 (토큰 절약)
    let priority: String
    let estimatedDuration: Int?
    let suggestedHour: Int?
    let suggestedMinute: Int?     // 분 단위 (0, 15, 30, 45 등)
    let daysFromToday: Int?       // 오늘로부터 며칠 후 (0=오늘, 1=내일, ...)
    let recurrence: String?       // 반복 주기 (none/daily/weekly/monthly/yearly)
    let keywords: [String]?       // 선택적 (토큰 절약)
}

// ============================================================
// MARK: - 에러 정의
// ============================================================

enum GeminiError: Error, LocalizedError {
    case invalidURL
    case noData
    case noContent
    case parsingFailed
    case apiError(Int)
    case rateLimited
    case usageBlocked(String)  // 안전장치에 의해 차단됨

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "error_invalid_url".localized
        case .noData: return "error_no_data".localized
        case .noContent: return "error_no_content".localized
        case .parsingFailed: return "error_parsing_failed".localized
        case .apiError(let code): return String(format: "API %@ (code: \(code))", L10n.alertError)
        case .rateLimited: return L10n.rateLimitError
        case .usageBlocked(let reason): return reason
        }
    }
}
