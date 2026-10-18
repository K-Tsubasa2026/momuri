# 무료 개인 개발자 계정으로 내 아이폰에 설치하기 위한 프로젝트를 만든다.
# 개인 계정이 지원하지 않는 Screen Time(Family Controls)과 건강 기록 접근 키를 뺀다.
import re

s = open('project.yml').read()
s = s.replace('name: Momuri\n', 'name: MomuriDevice\n', 1)
s = s.replace('        com.apple.developer.family-controls: true\n', '')
s = s.replace('        com.apple.developer.healthkit.access: []\n', '')
s = s.replace('      - target: MomuriMonitor\n      - target: MomuriReport\n', '')
s = re.sub(r'\n  MomuriMonitor:\n.*?(?=\n  MomuriTests:)', '\n', s, flags=re.S)
s = re.sub(r'\n  MomuriTests:\n.*', '\n', s, flags=re.S)
s += '''schemes:
  Momuri:
    build:
      targets:
        Momuri: all
'''
# 자동 서명이 App Group·HealthKit을 프로필에 등록하도록 능력(capability)을 켠다
caps = '''    attributes:
      SystemCapabilities:
        com.apple.ApplicationGroups.iOS:
          enabled: 1
        com.apple.HealthKit:
          enabled: 1
'''
widget_caps = '''    attributes:
      SystemCapabilities:
        com.apple.ApplicationGroups.iOS:
          enabled: 1
'''
s = s.replace('  Momuri:\n    type: application\n', '  Momuri:\n    type: application\n' + caps, 1)
s = s.replace('  MomuriWidget:\n    type: app-extension\n', '  MomuriWidget:\n    type: app-extension\n' + widget_caps, 1)
# 개인 계정은 App Group을 프로필에 넣지 못해서 뺀다 (앱은 자체 저장소를 쓰고, 위젯은 데이터를 못 읽는다)
s = s.replace('        com.apple.security.application-groups: [group.com.rymchoi.momuri]\n', '')
s = s.replace('''        com.apple.ApplicationGroups.iOS:
          enabled: 1
''', '')
s = s.replace('''    attributes:
      SystemCapabilities:
    platform''', '    platform')
s = s.replace('''    type: application
        com.apple.HealthKit:''', '''    type: application
    attributes:
      SystemCapabilities:
        com.apple.HealthKit:''')
# 원래 프로젝트의 entitlements 파일을 덮어쓰지 않도록 따로 둔다
s = re.sub(r'path: (\w+)/(\w+)\.entitlements', r'path: build-device/entitlements/\2.entitlements', s)
open('project-device.yml', 'w').write(s)
