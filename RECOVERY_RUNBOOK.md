# アサインメント評価システム：復旧手順書（学校用）

> 状態：**復旧手順の設計段階・復元実験は未実施**。
> この文書だけで元どおり復元できる保証はありません。生徒の実名・成績を本格登録する前に学校の情報管理担当者と確認すること。
>
> 本番のSupabaseを「Reset」「Delete」「Truncate」したり、CSVを本番テーブルに上書きインポートしないこと。

## 現在確保できている資産
- GitHub：フロントエンド `index.html`、教員管理Edge Function、**一部の**Supabase SQL（共有/RLSと担当割当）。**初期テーブル定義・全DB関数・認証設定の完全なバックアップではない**。
- 学校管理Googleドライブ：ユーザーが手動で出力したデータ入りテーブルのCSV。空のテーブルはデータが無いためファイルなし。
- 注：CSVの列に含まれるID（UUID）は、`auth.users` の教員IDや別テーブルの外部キーを参照します。**CSVを新しいDBに順番に読み込めば動く、というものではない**。

## 復元対象と必要な準備
| 対象 | 手元の保存物 | 復元上の問題 |
|---|---|---|
| 画面・処理 | GitHubのHTML/Edge Function | 新しいSupabaseのURL・公開キー・Edge Function配置が必要 |
| 教員ログイン | 現在のSupabase Auth上に存在 | CSVのprofilesだけではログイン不可。教員アカウントは別途再発行・UUID照合が必要 |
| アサインメント・評価対象 | projects/targets.csv | created_by, project_idを参照する |
| ルーブリック | criteria.csv | descriptorsなどのJSON型の扱いに注意 |
| 評価記録・点数 | assessments/assessment_scores.csv | teacher_id/assessment_id/criterion_id の整合性が必須 |
| 参加教員・担当割当 | project_members/project_teacher_criteria.csv（空ならなし） | 存在する教員IDと基準IDが必要 |
| セキュリティ | GitHubの一部SQL | Auth・RLS・トリガー・既存テーブル構造の完全コピーは未取得 |

## 現時点で行う、**本番DBを変更しない**追加保管
1. Supabase SQL Editorで [schema_inventory.sql](supabase/diagnostics/schema_inventory.sql) を実行する。
2. 結果をCSVで保存し、学校管理Googleドライブの**日付付きバックアップフォルダー**に格納する。
3. [rls_policy_snapshot.sql](supabase/diagnostics/rls_policy_snapshot.sql) も実行し、結果を同様に保存する。
4. これらは列の構成とRLS条件の**点検用控え**であり、**完全なCREATE TABLE/関数定義のバックアップではない**ことを記録する。
5. Driveの共有相手が必要最小限であることを確認し、個人用ドライブ・公開GitHub・共有リンクへCSVを置かない。

## 障害が起きたとき
1. **本番アプリでの評価入力を一時停止**し、障害時刻を記録。
2. Supabase Status／プロジェクト状態／SQLログを確認。接続障害だけなら復元せず待つ。
3. 最新のDriveバックアップの日付・内容・件数を調べる。
4. 新しい**検証用Supabaseプロジェクト**を別途確保できる場合のみ、学校の管理者権限でテーブル構造とAuthを再構築してから、関係順・UUID整合性を確認しつつCSVを取り込む。
5. 認証の再発行・UUIDの付け替えが必要な場合、データ修復計画と整合性検査を作成。ここは自動手順化していないため、安易にCSVをアップロードしない。
6. 評価数、点数、ルーブリック、権限、ログイン、CSV出力を検証後、学校側の承認を得て切り替える。
7. 本番Supabaseのデータを削除する操作は**行わない**。

## より確実なバックアップに移行する案
- 現在のFreeプランには自動DBバックアップが付かない。SupabaseはFreeの場合CLIの`db dump`による手動オフサイト保管を推奨。
- 学校PCにインストール制限があるため、情報システム担当者の管理する機器、または適切に権限分離したクラウド実行環境で、**認証情報を秘密として管理し**、完全な論理バックアップを実施するのが望ましい。
- GitHub Actionsなど外部実行環境での自動化を検討する際は、教育情報の外部転送・保管の許可、シークレットの扱い、暗号化、保持期限、復元試験を確認する。**公開リポジトリのArtifactに生徒情報を出さない**。
- Supabase Pro等の公式バックアップも選択肢。費用と学校の方針に従って選ぶ。

## 本番利用の判断
現在のCSVは**取り出せること**の検証にとどまる。**戻せること**の検証は済んでいない。
評価の重要性や個人情報保護規程に応じて、学校の担当者がバックアップ／復元の受け入れ判断を行ってから本格運用すること。

参考： https://supabase.com/docs/guides/platform/backups
公式のバックアップ/復元： https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore
