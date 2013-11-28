kadai2
======

※この README.md は ruby-topology のものをベースにしています。
※必要に応じて書き換える。

使用法
------

おなじみ `trema run` で実行すると、トポロジ情報がテキストで見えます。

スイッチ 3 台の三角形トポロジ:

```shell
$ trema run ./routing-switch.rb -c triangle.conf
```

スイッチ 10 台のフルメッシュ:

```shell
$ trema run ./routing-switch.rb -c fullmesh.conf
```

スイッチやポートを落としたり上げたりしてトポロジの変化を楽しむ:
(以下、別ターミナルで)

```shell
$ trema kill 0x1  # スイッチ 0x1 を落とす
$ trema up 0x1  # 落としたスイッチ 0x1 をふたたび起動
$ trema port_down --switch 0x1 --port 1  # スイッチ 0x1 のポート 1 を落とす
$ trema port_up --switch 0x1 --port 1  # 落としたポートを上げる
```

graphviz でトポロジ画像を出す:

```shell
$ trema run "./routing-switch.rb graphviz /tmp/topology.png" -c fullmesh.conf
```

LLDP の宛先 MAC アドレスを任意のやつに変える:

```shell
$ trema run "./routing-switch.rb --destination_mac 11:22:33:44:55:66" -c fullmesh.conf
```
