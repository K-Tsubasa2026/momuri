import Foundation

extension String {
    /// 한국어로 저장되는 값(헬스 부위, 단위 등)을 지금 화면 언어로 보여 준다.
    /// 카탈로그에 없는 값(사용자가 직접 적은 것)은 그대로 둔다.
    var localizedValue: String {
        Bundle.main.localizedString(forKey: self, value: self, table: nil)
    }
}

/// localizedValue 로 보여 주는 저장값들. 코드에 리터럴로 없어서 여기 적어 두면 카탈로그에 남는다.
private let storedValueKeys: [LocalizedStringResource] = [
    // 헬스 부위
    "가슴", "등", "하체", "어깨", "팔", "복근", "유산소",
    // 단위
    "회", "문제", "분", "페이지",
    // 운동 종목 추천
    "벤치프레스", "인클라인 덤벨프레스", "체스트 플라이", "딥스", "푸시업",
    "랫풀다운", "바벨 로우", "시티드 로우", "데드리프트", "풀업",
    "스쿼트", "레그프레스", "런지", "레그 컬", "레그 익스텐션",
    "오버헤드 프레스", "사이드 레터럴 레이즈", "리어 델트 플라이", "업라이트 로우",
    "바벨 컬", "해머 컬", "트라이셉스 푸시다운", "오버헤드 익스텐션",
    "크런치", "플랭크", "레그 레이즈", "행잉 레그 레이즈",
    // 공유 서버 오류 (server/index.js)
    "이름이 필요해요", "루틴 정보가 올바르지 않아요", "잠시 뒤에 다시 시도해 주세요", "초대 코드를 찾을 수 없어요",
    "공유를 찾을 수 없어요", "만든 사람만 바꿀 수 있어요", "days 배열이 필요해요", "보낼 사람을 찾을 수 없어요",
    "조금 뒤에 다시 보내 주세요", "시간 형식이 아니에요", "인증이 필요해요", "너무 커요", "JSON 형식이 아니에요", "서버 오류",
]

extension Locale {
    /// 앱이 실제로 쓰는 언어(한국어·일본어)의 로케일. 기기 지역과 상관없이 날짜 표기를 화면 언어에 맞춘다.
    static var app: Locale {
        Bundle.main.preferredLocalizations.first == "ja" ? Locale(identifier: "ja_JP") : Locale(identifier: "ko_KR")
    }
}
