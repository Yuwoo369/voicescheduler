// GoogleCalendarService.swift
// Google Calendar API를 사용하여 일정을 조회하고 등록합니다.
// 사용자가 할 일 카드를 드래그해서 시간대에 놓으면
// 이 서비스를 통해 실제 구글 캘린더에 일정이 저장됩니다.

import Foundation

// ============================================================
// MARK: - Google Calendar 서비스
// ============================================================

class GoogleCalendarService {

    // Singleton 패턴
    static let shared = GoogleCalendarService()
    private init() {}

    // Google Calendar API 기본 URL
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    // --------------------------------------------------------
    // MARK: - 일정 생성하기
    // --------------------------------------------------------

    /// 구글 캘린더에 새 일정을 등록합니다
    /// - Parameters:
    ///   - accessToken: 구글 API 접근 토큰
    ///   - title: 일정 제목
    ///   - date: 일정 날짜 (기본값: 오늘)
    ///   - hour: 시작 시간 (0-23)
    ///   - minute: 시작 분 (0-59, 기본값: 0)
    ///   - duration: 소요 시간 (분)
    ///   - recurrence: 반복 주기 (기본값: 없음)
    ///   - completion: 결과 콜백
    func createEvent(
        accessToken: String,
        title: String,
        date: Date = Date(),
        hour: Int,
        minute: Int = 0,
        duration: Int = 60,
        recurrence: Recurrence = .none,
        completion: @escaping (Result<CalendarEvent, Error>) -> Void
    ) {
        #if DEBUG
        print("📅 createEvent 호출됨 - 제목: \(title), 시간: \(hour)시 \(minute)분")
        #endif

        // 데모 모드: mock 성공 반환
        if accessToken == "demo_token" {
            let calendar = Calendar.current
            var startComponents = calendar.dateComponents([.year, .month, .day], from: date)
            startComponents.hour = hour
            startComponents.minute = minute
            let startDate = calendar.date(from: startComponents) ?? date
            let endDate = calendar.date(byAdding: .minute, value: duration, to: startDate) ?? startDate
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]

            let mockEvent = CalendarEvent(
                id: UUID().uuidString,
                summary: title,
                start: EventDateTime(dateTime: dateFormatter.string(from: startDate), timeZone: TimeZone.current.identifier),
                end: EventDateTime(dateTime: dateFormatter.string(from: endDate), timeZone: TimeZone.current.identifier)
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion(.success(mockEvent))
            }
            return
        }

        // API URL: /calendars/primary/events
        // primary = 사용자의 기본 캘린더
        let urlString = "\(baseURL)/calendars/primary/events"
        guard let url = URL(string: urlString) else {
            completion(.failure(CalendarError.invalidURL))
            return
        }

        // 시작 시간 계산 (지정된 날짜 + 지정된 시간 + 분)
        let calendar = Calendar.current
        var startComponents = calendar.dateComponents([.year, .month, .day], from: date)
        startComponents.hour = hour
        startComponents.minute = minute

        guard let startDate = calendar.date(from: startComponents) else {
            completion(.failure(CalendarError.invalidDate))
            return
        }

        // 종료 시간 = 시작 시간 + 소요 시간
        guard let endDate = calendar.date(byAdding: .minute, value: duration, to: startDate) else {
            completion(.failure(CalendarError.invalidDate))
            return
        }

        // ISO 8601 형식으로 날짜 변환 (구글 API가 요구하는 형식)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        // API 요청 바디 생성
        var eventData: [String: Any] = [
            "summary": title,  // 일정 제목
            "start": [
                "dateTime": dateFormatter.string(from: startDate),
                "timeZone": TimeZone.current.identifier  // 사용자의 시간대
            ],
            "end": [
                "dateTime": dateFormatter.string(from: endDate),
                "timeZone": TimeZone.current.identifier
            ],
            // 알림 설정 (30분 전, 10분 전)
            "reminders": [
                "useDefault": false,
                "overrides": [
                    ["method": "popup", "minutes": 30],
                    ["method": "popup", "minutes": 10]
                ]
            ]
        ]

        // 반복 주기가 있으면 추가
        if let rrule = recurrence.rrule {
            eventData["recurrence"] = [rrule]
        }

        // HTTP 요청 생성
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: eventData)
        } catch {
            completion(.failure(error))
            return
        }

        // API 호출
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // HTTP 상태 코드 확인
            if let httpResponse = response as? HTTPURLResponse {
                #if DEBUG
                print("Calendar API 응답 코드: \(httpResponse.statusCode)")
                #endif

                if httpResponse.statusCode != 200 {
                    // 에러 응답 로깅
                    if let data = data,
                       let errorString = String(data: data, encoding: .utf8) {
                        #if DEBUG
                        print("Calendar API 에러: \(errorString)")
                        #endif
                    }
                    completion(.failure(CalendarError.apiError(httpResponse.statusCode)))
                    return
                }
            }

            // 성공 응답 파싱
            guard let data = data else {
                completion(.failure(CalendarError.noData))
                return
            }

            do {
                let event = try JSONDecoder().decode(CalendarEvent.self, from: data)
                completion(.success(event))
            } catch {
                #if DEBUG
                print("이벤트 파싱 에러: \(error)")
                #endif
                completion(.failure(error))
            }
        }.resume()
    }

    // --------------------------------------------------------
    // MARK: - 특정 날짜 일정 가져오기
    // --------------------------------------------------------

    /// 특정 날짜의 일정 목록을 가져옵니다
    /// - Parameters:
    ///   - date: 조회할 날짜
    ///   - accessToken: 구글 API 접근 토큰
    ///   - completion: 결과 콜백 (성공 시 CalendarEvent 배열)
    func getEvents(
        for date: Date,
        accessToken: String,
        completion: @escaping (Result<[CalendarEvent], Error>) -> Void
    ) {
        // 해당 날짜의 시작/끝 시간 계산
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            completion(.failure(CalendarError.invalidDate))
            return
        }

        // ISO 8601 형식으로 변환
        let dateFormatter = ISO8601DateFormatter()

        // URL 쿼리 파라미터 구성
        guard var components = URLComponents(string: "\(baseURL)/calendars/primary/events") else {
            completion(.failure(CalendarError.invalidURL))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: dateFormatter.string(from: startOfDay)),
            URLQueryItem(name: "timeMax", value: dateFormatter.string(from: endOfDay)),
            URLQueryItem(name: "singleEvents", value: "true"),  // 반복 일정을 개별로 표시
            URLQueryItem(name: "orderBy", value: "startTime")   // 시작 시간순 정렬
        ]

        guard let url = components.url else {
            completion(.failure(CalendarError.invalidURL))
            return
        }

        // HTTP 요청 생성
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        // API 호출
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // HTTP 상태 코드 확인
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                if let data = data,
                   let errorString = String(data: data, encoding: .utf8) {
                    #if DEBUG
                    print("Calendar API 에러 (일정 조회): \(errorString)")
                    #endif
                }
                completion(.failure(CalendarError.apiError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                completion(.failure(CalendarError.noData))
                return
            }

            do {
                let listResponse = try JSONDecoder().decode(CalendarEventList.self, from: data)
                completion(.success(listResponse.items ?? []))
            } catch {
                #if DEBUG
                print("이벤트 목록 파싱 에러: \(error)")
                #endif
                completion(.failure(error))
            }
        }.resume()
    }

    // --------------------------------------------------------
    // MARK: - 일정 삭제하기
    // --------------------------------------------------------

    /// 구글 캘린더에서 일정을 삭제합니다
    /// - Parameters:
    ///   - accessToken: 구글 API 접근 토큰
    ///   - eventId: 삭제할 일정의 ID
    ///   - completion: 결과 콜백
    func deleteEvent(
        accessToken: String,
        eventId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let urlString = "\(baseURL)/calendars/primary/events/\(eventId)"
        guard let url = URL(string: urlString) else {
            completion(.failure(CalendarError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // 204 No Content = 성공적으로 삭제됨
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 204 {
                completion(.success(()))
            } else {
                completion(.failure(CalendarError.deleteFailed))
            }
        }.resume()
    }
}

// ============================================================
// MARK: - 캘린더 이벤트 모델
// ============================================================

/// 구글 캘린더 일정 데이터 모델
struct CalendarEvent: Codable, Identifiable {
    var id: String?            // 일정 고유 ID
    var summary: String?       // 일정 제목
    var description: String?   // 일정 설명
    var start: EventDateTime?  // 시작 시간
    var end: EventDateTime?    // 종료 시간
    var htmlLink: String?      // 웹에서 볼 수 있는 링크

    // 시작 시간을 Date로 변환하는 편의 프로퍼티
    var startDate: Date? {
        guard let dateTimeString = start?.dateTime else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateTimeString)
            ?? ISO8601DateFormatter().date(from: dateTimeString)
    }

    // 시작 시간(시)을 반환하는 편의 프로퍼티
    var startHour: Int? {
        guard let date = startDate else { return nil }
        return Calendar.current.component(.hour, from: date)
    }
}

/// 이벤트 시간 정보
struct EventDateTime: Codable {
    var dateTime: String?  // 날짜+시간 (ISO 8601)
    var date: String?      // 날짜만 (종일 일정용)
    var timeZone: String?  // 시간대
}

/// 이벤트 목록 응답
struct CalendarEventList: Codable {
    var items: [CalendarEvent]?
}

// ============================================================
// MARK: - 에러 정의
// ============================================================

enum CalendarError: Error, LocalizedError {
    case invalidURL
    case invalidDate
    case noData
    case apiError(Int)
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "잘못된 URL입니다"
        case .invalidDate: return "날짜 계산에 실패했습니다"
        case .noData: return "서버에서 데이터를 받지 못했습니다"
        case .apiError(let code): return "API 에러 (코드: \(code))"
        case .deleteFailed: return "일정 삭제에 실패했습니다"
        }
    }
}
