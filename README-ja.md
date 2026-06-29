# Azure HorizonDB 入門

**Azure HorizonDB** を使い始めるための、短時間で実行可能なデモです。クラスターをデプロイし、データを読み込み、レプリカから読み取り、フェイルオーバーに耐える流れを、実際のクラスター上でエンドツーエンドに確認します。

> Azure HorizonDB は **パブリック プレビュー** です。リソース プロバイダーは `Microsoft.HorizonDb`、API は `2026-01-20-preview` です。利用可能リージョンや CLI の仕様は頻繁に変わります。顧客向けに案内する前に、検証済みのリージョンを固定し、全体をドライランしてください。

---

## このデモで示すこと

| ステップ | 示す内容 | 方法 |
| ---- | ------------- | --- |
| 1 | レプリカ付きクラスターをデプロイする | CLI（`az horizondb create`）または下のボタン |
| 2 | 事前作成されたストアフロント データを読み込む | **読み取り/書き込み** エンドポイントに対して `psql` を実行 |
| 3 | レプリカから読み取りをスケールアウトする | **リーダー** エンドポイントに対して `psql` を実行（書き込みが拒否されることも確認） |
| 4 | 読み取り停止なしでフェイルオーバーする | ポータルで強制実行し、Cloud Shell から時間を計測 |

ステップ 1 でプロビジョニングしたレプリカは、ステップ 3 で読み取りを処理するノードであると同時に、ステップ 4 でフェイルオーバー先の候補にもなります。つまり、スタンバイは読み取り可能で、かつフェイルオーバー候補でもあります。

---

## Azure へデプロイ

[![Azure へデプロイ](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fberenguel%2FAzure-HorizonDB%2Fmain%2Finfra%2Fazuredeploy.json)

このリポジトリを push した後、上のボタン URL を編集してください。`USER`/`REPO`（既定ブランチが異なる場合は `main` も）を置き換え、raw の `infra/azuredeploy.json` を指すようにします。このボタンは、テンプレートが事前読み込みされたポータルのカスタム デプロイ画面を開きます。管理者パスワードを入力し、リージョンを選択してください。

---

## 前提条件

- **Azure CLI** と **`psql`** クライアント（新しいサーバーに対して古い `psql` を使っても問題ありません。この例では `psql` 16 から PG 17 に問題なく接続できます）。
- Azure サブスクリプション
- `./scripts/00-prereqs.sh` を一度実行してください。ツールを確認し、プレビュー版の `horizondb` 拡張機能をインストールし、**リソース プロバイダーを登録**します（サブスクリプションごとに一度だけ必要になります。詳細は下記）。

### パブリック プレビューでも避けられない 2 つのこと

- **プロバイダー登録は引き続き必要です。** 「パブリック プレビュー」によりサインアップの制限はなくなりますが、ARM 名前空間はサブスクリプションに登録されている必要があります。登録されていない場合、`create` は `MissingSubscriptionRegistration` で失敗します。
  ```bash
  az provider register --namespace Microsoft.HorizonDb   # その後 "Registered" になるまで待つ
  ```

- **拡張機能はプレビュー専用**のため、初回の `az horizondb` 呼び出し時にインストールを促されます。`00-prereqs.sh` は `extension.dynamic_install_allow_preview=true` を事前に設定するため、デプロイを中断せずにインストールできます。

---

## リージョン

プレビューは **Central US、West US 2、West US 3、Australia East、Sweden Central** で利用できます。
フェイルオーバー手順には可用性ゾーンが必要です。Central US、Australia East、Sweden Central はいずれも可用性ゾーンをサポートしています。

---

## クイックスタート

### ステップ 1: 新規デプロイ

```bash
git clone https://github.com/berenguel/Azure-HorizonDB.git
cd Azure-HorizonDB

chmod +x scripts/*.sh       # 新規 clone では実行ビットが保持されていない場合があります
cp .env.example .env        # 先頭のブロックを編集: サブスクリプション、リージョン、管理者ユーザー、パスワード
./scripts/00-prereqs.sh     # サブスクリプション + ツール + 拡張機能 + プロバイダー登録
./scripts/01-deploy-cli.sh  # クラスターを作成（数分かかります）し、エンドポイントを .env に書き込み
```

`.env` に `SUBSCRIPTION` を設定してください（サブスクリプション **ID** が最も簡単です。引用符は不要です）。スクリプトが `az account set` を実行するため、誤ったサブスクリプションへデプロイすることを防げます。

### ステップ 1.1: ネットワーク

次に、ポータルでクラスターの **Networking** ページを開き、**クライアント IP 用のファイアウォール規則を追加**します。

```bash
curl -s ifconfig.me
```

ネットワーク設定はポータル限定です。CLI 拡張機能ではまだ利用できません。そのため、この手順を行わないと `psql` が接続できません。

### ステップ 1.2: 接続テスト

```bash
source .env
psql "host=$RW_ENDPOINT port=5432 dbname=$DB_NAME user=$ADMIN_USER sslmode=require" -c "select version();"

```

### ステップ 2: データの読み込み

`.env` でデータ サイズを調整できます（`CUSTOMERS`、`PRODUCTS`、`ORDERS`）。既定値では約 50 万件の注文 / 約 125 万件の明細が生成されます。
すぐに試したい場合: `CUSTOMERS=5000 PRODUCTS=200 ORDERS=50000 ./scripts/02-load-data.sh`。

```bash
./scripts/02-load-data.sh          # スキーマ + 事前生成データ（読み取り/書き込みエンドポイント）
```

### ステップ 3: レプリカから読み取りをスケールアウト

```bash
./scripts/03-read-from-replica.sh  # リーダー エンドポイントで分析 + 読み取り専用であることを証明
```

### ステップ 4: フェイルオーバー デモ

フェイルオーバーはポータルでトリガーします（クラスター -> High availability -> forced failover）。
`04-failover-watch.sh` を実行してライブで監視します。

```bash
# 2 つのターミナルで実行し、その後ポータルで強制フェイルオーバーを 1 回トリガーします:
./scripts/04-failover-watch.sh        # ターミナル 1 - リーダー エンドポイント: 読み取りは維持される
./scripts/04-failover-watch.sh rw     # ターミナル 2 - 読み取り/書き込みエンドポイント: 書き込み停止時間を計測
```

このスクリプトは 1 秒に 1 回ポーリングし、エンドポイントがサービスを提供しているかをシンプルな表現で報告します
（`up - primary, accepting writes` / `up - replica, serving reads` / `DOWN - not reachable`）。
読み取り/書き込みエンドポイントでは、サービス復旧時に計測した `~Ns` のギャップも出力します。これが画面で示されるフェイルオーバー時間です。リーダー エンドポイントでの読み取りは停止しないはずです。

> 興味がある方向けに、`scripts/` にはフェイルオーバー用スクリプトがさらに 2 つあります。`05-failover-timer.sh`
> （インストール不要の連続 bash タイマー）と `06-failover-measure.py`（サブ秒精度、
> `pip install --user "psycopg[binary]"` が必要）です。


### ステップ 5: リソースの削除

```bash
# すべて削除
./scripts/99-teardown.sh           # 完了後にすべて削除
```

---

### 既存のクラスター（または切断後の Cloud Shell）

Cloud Shell は一時的な環境です。セッションを閉じると `.env` は失われます。クラスター自体には影響しません（Azure 上に残っています）。そのため、ライブ状態から `.env` を再構築してください。

```bash
./scripts/bootstrap-env.sh                                   # rg-horizon-demo / horizon-demo を使用
./scripts/bootstrap-env.sh <resource-group> <cluster-name>   # または名前を指定
```

このスクリプトは Azure から両方のエンドポイントを取得し、管理者ユーザーとパスワードの入力を求めます。**Azure はそれらを回答できません**（どちらも書き込み専用で、`az horizondb show` からは `null` が返ります）。そのため、覚えておく必要があります。


## コスト

これは、実行中に課金される複数レプリカのプレビュー クラスターをプロビジョニングします。作業が終わったらすぐに破棄してください: `./scripts/99-teardown.sh`（またはリソース グループを削除）。

---

## 実際に苦労して学んだ注意点

- **誤ったサブスクリプション -> 紛らわしい `AuthorizationFailed`。** Cloud Shell に再接続した後、別のアクティブ サブスクリプションになっていることがあります。その結果のエラーは、クラスターに対する権限問題のように見えます。まず必ず `az account show` を確認してください。
- **管理者ログインとパスワードは復元できません。** どちらも `az horizondb show` からは `null` が返ります。失った場合の選択肢は、ポータルでのパスワード リセット（クラスターで利用可能な場合）または再デプロイのみです。クラスター作成時に保存してください。
- **Cloud Shell の送信元 IP はセッション間で変わる場合があります**。再接続後に `psql` が突然タイムアウトする場合は、ファイアウォール規則を追加し直してください。
- **シードのファンアウト。** 注文ごとの明細数は `generate_series()` 内の `random()` ではなく、`order_id`（`1 + order_id % 4`）から導出しています。HorizonDB では、ランダムな上限を使うと注文ごとに明細がちょうど 1 件に集約されてしまいました。固定的な件数、ランダムな商品/数量にすることで、両方のエンジンで動作します。

---

## リポジトリ構成

```
infra/      azuredeploy.json（ボタンのターゲット）、azuredeploy.parameters.json、main.bicep（ソース）
scripts/    00 prereqs、01 deploy、02 load、03 replica read、04 watch、05 timer、
            06 measure（python）、99 teardown、bootstrap-env、_common.sh
sql/        schema.sql、seed.sql、read-queries.sql
.env.example
```
