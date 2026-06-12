#!/usr/bin/env bash
# 샘플 파드의 2nd NIC(net1) 부착과 IP를 검증하고 추적성을 데모한다.
# 사전: kubectl 컨텍스트가 대상 AKS로 설정됨, Multus + NAD + 파드 배포 완료.
set -euo pipefail

POD="${1:-dualnic-demo}"
NS="${2:-default}"

echo "== [1] 파드 상태 =="
kubectl -n "$NS" get pod "$POD" -o wide

echo "== [2] 네트워크 어노테이션(Multus) =="
kubectl -n "$NS" get pod "$POD" -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/networks}{"\n"}'

echo "== [3] 파드 인터페이스(net1 존재 확인) =="
kubectl -n "$NS" exec "$POD" -- ip -brief addr show

echo "== [4] net1 IP 추출 =="
NET1_IP=$(kubectl -n "$NS" exec "$POD" -- sh -c "ip -4 -o addr show net1 2>/dev/null | awk '{print \$4}'" || true)
if [ -n "${NET1_IP}" ]; then
  echo "net1 IP = ${NET1_IP}  (routable 서브넷 대역인지 확인)"
else
  echo "[WARN] net1 미발견 — Multus/NAD/어노테이션 구성을 확인하세요(DESIGN.md §8)."
fi

echo "== [5] (Approach B) egress 소스 IP 데모 =="
echo "외부에서 관찰되는 소스 IP가 노드 SNAT가 아닌 파드별 routable IP인지 확인하세요."
echo "예: kubectl -n $NS exec $POD -- curl -s https://ifconfig.me ; 또는 대상 리소스의 접근 로그 확인."
