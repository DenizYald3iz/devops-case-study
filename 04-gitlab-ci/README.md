# 04-gitlab-ci — CI/CD Pipeline

GitLab CI/CD ile otomatik build, güvenlik tarama ve Kubernetes deployment pipeline'ı.

## Pipeline Akışı

```
git push (main)
    │
    ▼
validate ──► build ──► scan ──► push ──► deploy ──► rollback
(hadolint)  (kaniko)  (trivy)  (latest  (kubectl   (kubectl
                               tag)     - MANUEL)   undo
                                                    - MANUEL)
```

## Aşamalar

| Stage | Job | Ne Yapar |
|---|---|---|
| validate | `validate_dockerfile` | Hadolint ile Dockerfile best-practice kontrolü |
| build | `build_image_kaniko` | Kaniko ile rootless image build + registry push |
| scan | `security_scan` | Trivy ile HIGH/CRITICAL zafiyet taraması |
| push | `tag_latest_main` | main branch ise `latest` tag eklenir |
| deploy | `deploy_production` | kubectl rolling update — **manuel onay** |
| rollback | `rollback_production` | `kubectl rollout undo` — **manuel, acil durum** |

## Gerekli CI/CD Değişkenleri

GitLab → Settings → CI/CD → Variables:

| Değişken | Açıklama |
|---|---|
| `CI_REGISTRY_USER` | GitLab registry kullanıcı adı (otomatik gelir) |
| `CI_REGISTRY_PASSWORD` | GitLab registry şifresi (otomatik gelir) |
| `CI_REGISTRY` | Registry adresi (otomatik gelir) |
| `KUBECONFIG_PROD` | `base64 -w0 ~/.kube/config` çıktısı — **gizli tutulmalı** |

`KUBECONFIG_PROD` üretmek için:
```bash
cat ~/.kube/config | base64 -w0
# Çıktıyı GitLab'a "Masked" olarak ekle
```

## Mimari Kararlar

### Neden Kaniko? (DinD yerine)
Docker-in-Docker Runner'ın `privileged: true` modunda çalışmasını gerektirir — bu host kernel'e tam erişim demektir. Kaniko aynı işi userspace'de yapar, root yetkisi gerekmez.

### Neden Trivy scan sonra push?
"Shift-Left Security" — güvenlik açığı olan image asla `latest` tag almaz ve production'a gidemez. Pipeline sırası: build → scan → push(latest) → deploy.

### Neden manual deploy?
Continuous Deployment değil **Continuous Delivery** felsefesi benimsendi. Production'a çıkış her zaman bir insanın onayına bağlı olmalıdır.

### Neden rollback stage?
Deploy sonrası kritik hata çıkarsa terminal açmaya gerek kalmadan GitLab UI'dan tek tıkla `kubectl rollout undo` çalışır.

### Neden `rules` (only/except yerine)?
`only/except` deprecated yaklaşımdır. `rules` daha okunabilir, `when: manual` gibi koşulları aynı blokta tanımlamayı sağlar.

## Runner Gereksinimleri

Pipeline `privileged: false` çalışır (Kaniko sayesinde). Gerekli olan:
- Docker executor veya Kubernetes executor
- Internet erişimi (gcr.io, aquasec registry)

## KUBECONFIG Güvenliği

`KUBECONFIG_PROD` değişkeni GitLab'da **Masked + Protected** olarak saklanmalıdır. Pipeline içinde:
```bash
echo "$KUBECONFIG_PROD" | base64 -d > kubeconfig
export KUBECONFIG=kubeconfig
```
Job bitince geçici dosya silinir, kubeconfig log'a yazdırılmaz.

