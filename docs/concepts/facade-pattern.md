# 파사드 패턴 (Facade Pattern)

복잡한 서브시스템 여러 개를 **하나의 단순한 인터페이스로 감싸** 클라이언트가 쉽게 쓰게 하는
**구조(Structural) 디자인 패턴**.

## 핵심 개념

- 여러 클래스·모듈의 복잡한 상호작용을 **하나의 진입점(Facade)**으로 통합.
- 클라이언트는 내부 구조를 몰라도 됨 → **결합도 감소**.
- "복잡한 걸 뒤에 숨기고, 간단한 창구만 노출."

## 구조

```
Client → [Facade] → SubsystemA
                  → SubsystemB
                  → SubsystemC
```

클라이언트는 Facade만 호출, Facade가 내부 서브시스템을 조율한다.

## 예시 (주문 처리)

```python
class OrderFacade:
    def __init__(self):
        self.inventory = Inventory()
        self.payment = Payment()
        self.shipping = Shipping()

    def place_order(self, item, card):
        if not self.inventory.check(item):
            raise ValueError("품절")
        self.payment.charge(card)
        self.shipping.send(item)
        return "주문 완료"

# 클라이언트: 내부 3개 시스템을 몰라도 한 줄
OrderFacade().place_order("책", card)
```

→ 클라이언트가 재고·결제·배송을 개별 호출하지 않고 `place_order` 하나로 끝.

## 장점 / 단점

| 장점 | 단점 |
| --- | --- |
| 복잡성 은닉, 사용 단순화 | Facade가 **God Object**로 비대해질 수 있음 |
| 클라이언트–서브시스템 **결합도↓** | 서브시스템 직접 접근이 필요할 땐 우회 필요 |
| 서브시스템 교체·리팩터링 용이 | 계층이 하나 늘어남 |

## 언제 쓰나

- 복잡한 라이브러리/레거시 시스템에 **단순한 API**를 얹고 싶을 때.
- 계층 간 **명확한 진입점**이 필요할 때 (예: 서비스 레이어).
- 서브시스템은 그대로 두되 **자주 쓰는 흐름만 편하게** 노출하고 싶을 때.

## 혼동 주의

- **Adapter**: 인터페이스 "변환"(호환) 목적 / **Facade**: 인터페이스 "단순화" 목적.
- **Mediator**: 객체 간 상호작용 중재(양방향) / **Facade**: 단방향 단순 창구.
