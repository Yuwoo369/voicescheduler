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
    // MARK: - API 설정
    // --------------------------------------------------------

    // Gemini API 키 (SecretsManager에서 안전하게 로드)
    private var apiKey: String {
        return SecretsManager.shared.geminiAPIKey
    }

    // API 엔드포인트 URL
    // gemini-2.0-flash 모델 사용 (안정적이고 빠름)
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

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

        // ⚠️ 안전장치: API 사용 가능 여부 확인
        let usageGuard = APIUsageGuard.shared
        let (allowed, reason) = usageGuard.canMakeRequest()

        if !allowed {
            #if DEBUG
            print("🛡️ API 요청 차단됨: \(reason ?? "unknown")")
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
                maxOutputTokens: 512   // 출력 토큰 절반으로 감소
            )
        )

        // HTTP 요청 생성
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

                // JSON 응답을 TodoItem 배열로 변환
                let todoItems = self.parseTodoItems(from: text)
                #if DEBUG
                print("✅ Gemini 분석 성공: \(todoItems.count)개 할 일 추출")
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
    // - maxOutputTokens: 1024 → 512 (50% 감소)
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

        // 현재 시간
        let currentHour = calendar.component(.hour, from: now)

        // 간단한 요일 오프셋 (Sun=1부터)
        let wkOff = "Su:\((8-weekday)%7),Mo:\((9-weekday)%7),Tu:\((10-weekday)%7),We:\((11-weekday)%7),Th:\((12-weekday)%7),Fr:\((13-weekday)%7),Sa:\((14-weekday)%7)"

        return """
        You are a smart schedule assistant. Extract tasks with INTELLIGENT inference.
        Reply in \(language). JSON array only, no markdown.

        TODAY: \(today), CURRENT TIME: \(currentHour):00
        Weekday offsets: \(wkOff)
        User input: "\(text)"

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
        - If no date mentioned → daysFromToday: 0 (today)

        IMPORTANT: "내일 저녁" = daysFromToday:1, "tomorrow morning" = daysFromToday:1

        ## Recurrence
        - 매일/daily/毎日/每天/diario → daily
        - 매주/weekly/毎週/每周/semanal → weekly
        - 매월/monthly/毎月/每月/mensual → monthly
        - Default: none

        Output format (JSON array only):
        [{"title":"task name","priority":"high/medium/low","estimatedDuration":30,"suggestedHour":9,"suggestedMinute":0,"daysFromToday":0,"recurrence":"none"}]
        """
    }

    // --------------------------------------------------------
    // MARK: - 폴백 파서 (AI 실패 시 로컬 파싱)
    // --------------------------------------------------------

    /// AI 없이 간단한 규칙 기반으로 할 일을 추출합니다
    func fallbackParse(text: String) -> [TodoItem] {
        #if DEBUG
        print("🔄 폴백 파서 사용: \(text)")
        #endif

        // 빈 텍스트 체크
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        // 우선순위 키워드
        let highPriorityKeywords = ["중요", "급한", "긴급", "urgent", "important", "asap", "마감", "deadline"]
        let lowPriorityKeywords = ["나중에", "여유", "언젠가", "later", "sometime", "maybe"]

        // 시간 키워드 파싱
        var suggestedHour: Int? = nil
        let hourPatterns = [
            ("오전 (\\d{1,2})시", { (h: Int) in h }),
            ("오후 (\\d{1,2})시", { (h: Int) in h < 12 ? h + 12 : h }),
            ("(\\d{1,2})시", { (h: Int) in h }),
            ("(\\d{1,2})am", { (h: Int) in h }),
            ("(\\d{1,2})pm", { (h: Int) in h < 12 ? h + 12 : h }),
            ("(\\d{1,2}):00", { (h: Int) in h })
        ]

        for (pattern, transform) in hourPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text),
               let hour = Int(text[range]) {
                suggestedHour = transform(hour)
                break
            }
        }

        // 날짜 파싱
        var daysFromToday = 0
        if text.contains("내일") || text.lowercased().contains("tomorrow") {
            daysFromToday = 1
        } else if text.contains("모레") || text.lowercased().contains("day after") {
            daysFromToday = 2
        } else if text.contains("다음주") || text.lowercased().contains("next week") {
            daysFromToday = 7
        }

        // 요일 파싱
        let weekdays = [
            ("월요일", "monday", 2), ("화요일", "tuesday", 3), ("수요일", "wednesday", 4),
            ("목요일", "thursday", 5), ("금요일", "friday", 6), ("토요일", "saturday", 7), ("일요일", "sunday", 1)
        ]
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: Date())

        for (ko, en, target) in weekdays {
            if text.contains(ko) || text.lowercased().contains(en) {
                var diff = target - currentWeekday
                if diff <= 0 { diff += 7 }
                daysFromToday = diff
                break
            }
        }

        // 반복 파싱
        var recurrence: Recurrence = .none
        if text.contains("매일") || text.lowercased().contains("every day") || text.lowercased().contains("daily") {
            recurrence = .daily
        } else if text.contains("매주") || text.lowercased().contains("every week") || text.lowercased().contains("weekly") {
            recurrence = .weekly
        } else if text.contains("매월") || text.contains("매달") || text.lowercased().contains("monthly") {
            recurrence = .monthly
        }

        // 우선순위 결정
        var priority: Priority = .medium
        let lowerText = text.lowercased()
        for keyword in highPriorityKeywords {
            if lowerText.contains(keyword) {
                priority = .high
                break
            }
        }
        if priority == .medium {
            for keyword in lowPriorityKeywords {
                if lowerText.contains(keyword) {
                    priority = .low
                    break
                }
            }
        }

        // 제목 생성 (원본 텍스트를 정리, 첫 글자 대문자)
        var title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count > 50 {
            title = String(title.prefix(50)) + "..."
        }
        if let first = title.first {
            title = first.uppercased() + title.dropFirst()
        }

        let scheduledDate = calendar.date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()

        let todoItem = TodoItem(
            title: title,
            description: "",
            priority: priority,
            estimatedDuration: 60,
            suggestedHour: suggestedHour ?? 9,
            scheduledDate: scheduledDate,
            recurrence: recurrence,
            keywords: []
        )

        return [todoItem]
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

                // 날짜 계산 (오늘 + daysFromToday)
                let scheduledDate = Calendar.current.date(
                    byAdding: .day,
                    value: raw.daysFromToday ?? 0,
                    to: Date()
                ) ?? Date()

                // 반복 주기 매핑
                let recurrence: Recurrence
                switch raw.recurrence?.lowercased() {
                case "daily": recurrence = .daily
                case "weekly": recurrence = .weekly
                case "monthly": recurrence = .monthly
                case "yearly": recurrence = .yearly
                default: recurrence = .none
                }

                // 첫 글자 대문자
                let capitalizedTitle = raw.title.prefix(1).uppercased() + raw.title.dropFirst()

                return TodoItem(
                    title: capitalizedTitle,
                    description: raw.description,
                    priority: priority,
                    estimatedDuration: raw.estimatedDuration ?? 60,
                    suggestedHour: raw.suggestedHour,
                    suggestedMinute: raw.suggestedMinute ?? 0,
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
