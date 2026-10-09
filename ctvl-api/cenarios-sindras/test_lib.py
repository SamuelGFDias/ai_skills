"""Testes offline de lib.py (sem cofre, sem rede externa). Dados 100% sinteticos gerados por lib."""
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

AQUI = Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
import lib  # noqa: E402
SEQ = "1234567890" * 2   # sequencia nao-documental (mascara/sanitizacao), nao e CPF/CNS


def _soma_cpf(digitos: str, pesos_ini: int) -> int:
    return sum(int(d) * (pesos_ini - i) for i, d in enumerate(digitos))


def _cpf_oracle(c: str) -> bool:
    """Oraculo independente: formulacao 'mod 11 do somatorio ponderado'."""
    if len(c) != 11 or not c.isdigit() or len(set(c)) == 1:
        return False
    d1 = (_soma_cpf(c[:9], 10) * 10 % 11) % 10
    d2 = (_soma_cpf(c[:10], 11) * 10 % 11) % 10
    return c[9] == str(d1) and c[10] == str(d2)


def _dv_pis(pis11: str) -> str:
    """Algoritmo oficial do CNS definitivo (PIS): devolve '000D' ou '001D'."""
    soma = sum(int(d) * (15 - i) for i, d in enumerate(pis11))
    dv = 11 - soma % 11
    dv = 0 if dv == 11 else dv
    if dv == 10:
        soma += 2
        dv = 11 - soma % 11
        dv = 0 if dv == 11 else dv
        return "001" + str(dv)
    return "000" + str(dv)


class TestCpf(unittest.TestCase):
    def test_gerados_sao_validos_pelo_oraculo(self):
        for c in lib.gerar_cpfs(200):
            self.assertTrue(_cpf_oracle(c))
            self.assertTrue(lib.cpf_valido(c))

    def test_dv_alterado_e_invalido(self):
        for c in lib.gerar_cpfs(50):
            ruim = c[:-1] + str((int(c[-1]) + 1) % 10)
            self.assertFalse(lib.cpf_valido(ruim))

    def test_sequencia_repetida_tamanho_e_letras_sao_invalidos(self):
        self.assertFalse(lib.cpf_valido("1" * 11))
        self.assertFalse(lib.cpf_valido(lib.gerar_cpf(1)[:10]))
        self.assertFalse(lib.cpf_valido(lib.gerar_cpf(1) + "0"))
        self.assertFalse(lib.cpf_valido("abc" + lib.gerar_cpf(1)[3:]))
        self.assertFalse(lib.cpf_valido(""))

    def test_aceita_pontuacao_ao_validar(self):
        c = lib.gerar_cpf(3)
        com = f"{c[:3]}.{c[3:6]}.{c[6:9]}-{c[9:]}"
        self.assertTrue(lib.cpf_valido(com))

    def test_geracao_deterministica_e_distinta(self):
        self.assertEqual(lib.gerar_cpf(5), lib.gerar_cpf(5))
        self.assertEqual(len(set(lib.gerar_cpfs(300))), 300)


class TestCns(unittest.TestCase):
    def test_definitivo_segue_algoritmo_oficial(self):
        for s in range(1, 200):
            c = lib.gerar_cns(s, "definitivo")
            self.assertEqual(len(c), 15)
            self.assertIn(c[0], "12")
            self.assertEqual(c[11:], _dv_pis(c[:11]))
            self.assertTrue(lib.cns_valido(c))

    def test_provisorio_comeca_com_7_8_9_e_soma_multipla_de_11(self):
        for s in range(1, 200):
            c = lib.gerar_cns(s, "provisorio")
            self.assertIn(c[0], "789")
            self.assertEqual(sum(int(d) * (15 - i) for i, d in enumerate(c)) % 11, 0)
            self.assertTrue(lib.cns_valido(c))

    def test_ultimo_digito_alterado_e_invalido(self):
        for c in lib.gerar_cnss(60):
            ruim = c[:-1] + str((int(c[-1]) + 1) % 10)
            self.assertFalse(lib.cns_valido(ruim))

    def test_prefixo_invalido_e_tamanho(self):
        c = lib.gerar_cns(1, "definitivo")
        self.assertFalse(lib.cns_valido("5" + c[1:]))
        self.assertFalse(lib.cns_valido(c[:14]))
        self.assertFalse(lib.cns_valido("x" * 15))

    def test_mistura_definitivo_e_provisorio(self):
        iniciais = {c[0] for c in lib.gerar_cnss(40)}
        self.assertTrue(iniciais & set("12"))
        self.assertTrue(iniciais & set("789"))
        self.assertEqual(len(set(lib.gerar_cnss(200))), 200)


class TestNormalizacaoEPreparo(unittest.TestCase):
    def test_apenas_digitos(self):
        self.assertEqual(lib.apenas_digitos(" 12.3-4/5 a6 "), "123456")

    def test_preparar_normaliza_cpf_e_cns(self):
        c = lib.gerar_cpf(9)
        com = f"{c[:3]}.{c[3:6]}.{c[6:9]}-{c[9:]}"
        self.assertEqual(lib.preparar([com, c], "cpf"), [c, c])
        n = lib.gerar_cns(9)
        self.assertEqual(lib.preparar([f"{n[:4]} {n[4:8]} {n[8:12]} {n[12:]}"], "cns"), [n])

    def test_preparar_recusa_dv_invalido_sem_valor_na_mensagem(self):
        c = lib.gerar_cpf(9)
        ruim = c[:-1] + str((int(c[-1]) + 1) % 10)
        with self.assertRaises(lib.ValorInvalido) as cm:
            lib.preparar([c, ruim], "cpf")
        self.assertNotIn(ruim, str(cm.exception))
        self.assertIn("1", str(cm.exception))  # indice do item

    def test_preparar_tipo_desconhecido(self):
        with self.assertRaises(ValueError):
            lib.preparar(["1"], "rg")


class TestMascara(unittest.TestCase):
    def test_mascara_esperada(self):
        self.assertEqual(lib.aplicar_mascara(SEQ[:11], 3, 2), "123******01")
        self.assertEqual(lib.aplicar_mascara(SEQ[:11], 0, 2), "*********01")
        self.assertEqual(lib.aplicar_mascara(SEQ[:15], 3, 0), "123************")
        self.assertEqual(lib.aplicar_mascara(SEQ[:15], 0, 0), "*" * 15)

    def test_mascara_maior_que_valor(self):
        self.assertEqual(lib.aplicar_mascara("1234", 3, 2), "1234")


class TestLotes(unittest.TestCase):
    def test_divide_em_lotes(self):
        self.assertEqual([len(x) for x in lib.dividir_lotes(list(range(2500)), 1000)], [1000, 1000, 500])
        self.assertEqual(lib.dividir_lotes([1], 1000), [[1]])

    def test_padrao_1000_e_teto_5000(self):
        self.assertEqual(lib.LOTE_PADRAO, 1000)
        self.assertEqual(lib.MAX_LOTE, 5000)
        self.assertEqual(len(lib.dividir_lotes(list(range(5000)), 5000)), 1)
        with self.assertRaises(ValueError):
            lib.dividir_lotes(list(range(10)), 5001)
        with self.assertRaises(ValueError):
            lib.dividir_lotes(list(range(10)), 0)

    def test_lista_vazia_recusada(self):
        with self.assertRaises(lib.ListaVazia):
            lib.dividir_lotes([], 1000)


class TestMotivos(unittest.TestCase):
    def test_sanitizar_remove_ip_url_e_digitos_longos(self):
        s = lib.sanitizar_motivo("falha " + SEQ[:11] + " em https://x.y/z (X-Real-IP '10.20.30.40')")
        self.assertNotIn("10.20.30.40", s)
        self.assertNotIn(SEQ[:11], s)
        self.assertNotIn("https", s)

    def test_classificacao(self):
        c = lib.classificar_motivo
        self.assertEqual(c("The requested key name was not found on the key store (X-Real-IP '1.1.1.1')"), "transitorio")
        self.assertEqual(c("not enough input characters are left to successfully detokenize"), "entrada")
        self.assertEqual(c("The requested combination of tokentemplate and tokengroup was not found"), "template")
        self.assertEqual(c("The token group specified was not found in the database."), "grupo")
        self.assertEqual(c("Could not parse JSON input, perhaps it is too long."), "limite")
        self.assertEqual(c("User does not have permission"), "permissao")
        self.assertEqual(c("algo novo"), "outro")


def _item(**kw):
    return kw


class TestValidarResposta(unittest.TestCase):
    def test_sucesso(self):
        r = lib.validar_resposta_lote([{"status": "Succeed", "token": "abc"}] * 2, 2, "token")
        self.assertTrue(all(i.ok and i.valor == "abc" for i in r))

    def test_erro_de_negocio_vira_falha_do_item_sem_valor(self):
        resp = [{"status": "Succeed", "data": "1"}, {"status": "error", "reason": "The token group specified was not found in the database."}]
        r = lib.validar_resposta_lote(resp, 2, "data")
        self.assertTrue(r[0].ok)
        self.assertFalse(r[1].ok)
        self.assertIsNone(r[1].valor)
        self.assertEqual(r[1].categoria, "grupo")

    def test_status_diferente_de_succeed_e_falha_mesmo_com_campo(self):
        r = lib.validar_resposta_lote([{"status": "error", "data": "123", "reason": "x"}], 1, "data")
        self.assertFalse(r[0].ok)
        self.assertIsNone(r[0].valor)

    def test_succeed_sem_campo_e_falha_de_forma(self):
        r = lib.validar_resposta_lote([{"status": "Succeed"}], 1, "data")
        self.assertFalse(r[0].ok)
        self.assertEqual(r[0].categoria, "forma")

    def test_objeto_no_lugar_de_lista_e_detectado(self):
        with self.assertRaises(lib.RespostaInvalida) as cm:
            lib.validar_resposta_lote({"status": "error", "reason": "Could not parse JSON input, perhaps it is too long."}, 5156, "data")
        self.assertEqual(cm.exception.categoria, "limite")

    def test_tamanho_diferente_e_detectado(self):
        with self.assertRaises(lib.RespostaInvalida):
            lib.validar_resposta_lote([{"status": "error", "reason": "x"}], 3, "data")

    def test_item_que_nao_e_objeto(self):
        with self.assertRaises(lib.RespostaInvalida):
            lib.validar_resposta_lote(["x"], 1, "data")

    def test_texto_html_e_detectado(self):
        with self.assertRaises(lib.RespostaInvalida):
            lib.validar_resposta_lote("<html>401</html>", 1, "data")


class Roteiro:
    """Transporte falso: devolve respostas na ordem; registra corpos."""

    def __init__(self, *respostas):
        self.respostas = list(respostas)
        self.corpos = []

    def __call__(self, path, body):
        self.corpos.append((path, body))
        r = self.respostas.pop(0)
        return r(body) if callable(r) else r


def ok_tok(body):
    return 200, [{"status": "Succeed", "token": "t" + i["data"]} for i in body]


TRANSIENTE = {"status": "error", "reason": "The requested key name was not found on the key store (X-Real-IP '9.9.9.9')"}


def novo_cofre(*respostas, tentativas_dormir=None):
    t = Roteiro(*respostas)
    return lib.Cofre(t, usuario="u", dormir=lambda s: None), t


class TestTokenizeDetokenize(unittest.TestCase):
    def test_lista_vazia_nao_chama_o_cofre(self):
        cofre, t = novo_cofre()
        with self.assertRaises(lib.ListaVazia):
            lib.tokenize([], "T", cofre)
        with self.assertRaises(lib.ListaVazia):
            lib.detokenize([], "T", cofre)
        self.assertEqual(cofre.stats.chamadas, 0)

    def test_corpo_da_requisicao(self):
        cofre, t = novo_cofre(ok_tok)
        lib.tokenize(["111"], "SINDRAS_CPF", cofre)
        self.assertEqual(t.corpos[0][0], lib.URL_TOKENIZE)
        self.assertEqual(t.corpos[0][1], [{"tokengroup": "SES", "tokentemplate": "SINDRAS_CPF", "data": "111"}])

    def test_detokenize_corpo_so_com_campos_aceitos(self):
        cofre, t = novo_cofre((200, [{"status": "Succeed", "data": "111"}]))
        r = lib.detokenize(["abc"], "SINDRAS_CPF", cofre)
        self.assertEqual(set(t.corpos[0][1][0]), {"tokengroup", "token", "tokentemplate"})
        self.assertEqual(r[0].valor, "111")

    def test_divide_em_lotes_e_preserva_ordem(self):
        cofre, t = novo_cofre(ok_tok, ok_tok, ok_tok)
        valores = [str(i) for i in range(25)]
        r = lib.tokenize(valores, "T", cofre, lote=10)
        self.assertEqual([len(b) for _, b in t.corpos], [10, 10, 5])
        self.assertEqual([i.valor for i in r], ["t" + v for v in valores])

    def test_retry_absorve_falha_intermitente_so_dos_itens_afetados(self):
        def primeira(body):
            return 200, [{"status": "Succeed", "token": "a"}, TRANSIENTE, {"status": "Succeed", "token": "c"}]
        cofre, t = novo_cofre(primeira, (200, [{"status": "Succeed", "token": "b"}]))
        r = lib.tokenize(["1", "2", "3"], "T", cofre, tentativas=3)
        self.assertEqual([i.valor for i in r], ["a", "b", "c"])
        self.assertEqual(len(t.corpos[1][1]), 1)  # reenviou so o item transitorio
        self.assertEqual(cofre.stats.retries, 1)
        self.assertEqual(cofre.stats.itens_transitorios, 1)

    def test_falha_definitiva_nao_vira_dado_nem_valor_padrao(self):
        cofre, _ = novo_cofre((200, [TRANSIENTE]), (200, [TRANSIENTE]), (200, [TRANSIENTE]))
        r = lib.detokenize(["tok"], "T", cofre, tentativas=3)
        self.assertFalse(r[0].ok)
        self.assertIsNone(r[0].valor)
        self.assertEqual(r[0].categoria, "transitorio")

    def test_erro_de_negocio_nao_e_repetido(self):
        cofre, t = novo_cofre((200, [{"status": "error", "reason": "not enough input characters"}]))
        r = lib.detokenize(["x"], "T", cofre, tentativas=3)
        self.assertEqual(len(t.corpos), 1)
        self.assertFalse(r[0].ok)
        self.assertEqual(r[0].categoria, "entrada")

    def test_resposta_com_forma_errada_levanta_erro_do_cofre(self):
        cofre, _ = novo_cofre((200, {"status": "error", "reason": "Could not parse JSON input"}))
        with self.assertRaises(lib.ErroCofre) as cm:
            lib.tokenize(["1"], "T", cofre)
        self.assertEqual(cm.exception.categoria, "limite")

    def test_http_401_nao_repete_e_classifica(self):
        cofre, t = novo_cofre((401, "<html>"))
        with self.assertRaises(lib.ErroCofre) as cm:
            lib.detokenize(["x"], "T", cofre)
        self.assertEqual(cm.exception.categoria, "autenticacao")
        self.assertEqual(len(t.corpos), 1)

    def test_erro_de_rede_repete_e_depois_levanta(self):
        cofre, t = novo_cofre((None, "Timeout"), (None, "Timeout"))
        with self.assertRaises(lib.ErroCofre) as cm:
            lib.tokenize(["1"], "T", cofre, tentativas=2)
        self.assertEqual(cm.exception.categoria, "rede")
        self.assertEqual(len(t.corpos), 2)

    def test_mensagem_de_erro_nao_carrega_motivo_cru(self):
        cofre, _ = novo_cofre((200, {"status": "error", "reason": "Could not parse (X-Real-IP '8.8.8.8')"}))
        with self.assertRaises(lib.ErroCofre) as cm:
            lib.tokenize(["1"], "T", cofre)
        self.assertNotIn("8.8.8.8", str(cm.exception))

    def test_tentativas_invalidas(self):
        cofre, _ = novo_cofre()
        with self.assertRaises(ValueError):
            lib.tokenize(["1"], "T", cofre, tentativas=0)


class TestSegredos(unittest.TestCase):
    def test_mascarar_texto(self):
        lib.registrar_segredo("segredo-super-longo")
        s = lib.mascarar_texto("erro com segredo-super-longo e https://h.exemplo/x")
        self.assertNotIn("segredo-super-longo", s)
        self.assertNotIn("https", s)


class TestFake(unittest.TestCase):
    """Autoteste do servidor falso com a propria lib."""

    @classmethod
    def setUpClass(cls):
        import fake_dados
        cls.srv = fake_dados.iniciar(falha_a_cada=0, desabilitados=("sindras_cns_3_left",))
        cls.cofres = {u: lib.Cofre(lib.transporte_http(cls.srv.url, u, fake_dados.senha_de(u)), usuario=u, dormir=lambda s: None)
                      for u in fake_dados.USUARIOS}

    @classmethod
    def tearDownClass(cls):
        cls.srv.parar()

    def test_round_trip_preserva_digitos_visiveis_e_tamanho(self):
        cpfs = lib.gerar_cpfs(30)
        r = lib.tokenize(cpfs, "SINDRAS_CPF", self.cofres["sindras_svc_tokenize"])
        for c, i in zip(cpfs, r):
            self.assertTrue(i.ok)
            self.assertEqual(len(i.valor), 11)
            self.assertTrue(i.valor.isdigit())
            self.assertEqual(i.valor[:3], c[:3])  # CPF: só os 3 primeiros em claro (keep_right 0)
        d = lib.detokenize([i.valor for i in r], "SINDRAS_CPF", self.cofres["sindras_total"])
        self.assertEqual([i.valor for i in d], cpfs)
        m = lib.detokenize([i.valor for i in r], "SINDRAS_CPF", self.cofres["sindras_cpf_3_left_2_right"])
        self.assertEqual([i.valor for i in m], [lib.aplicar_mascara(c, 3, 2) for c in cpfs])

    def test_lote_acima_de_5000_devolve_objeto(self):
        cofre = self.cofres["sindras_total"]
        status, data = cofre.enviar(lib.URL_DETOKENIZE, [{"tokengroup": "SINDRAS", "tokentemplate": "SINDRAS_CPF", "token": "0" * 11}] * 5001)
        self.assertEqual(status, 200)
        self.assertIsInstance(data, dict)

    def test_usuario_nao_habilitado_e_classificado_como_permissao(self):
        t = lib.tokenize([lib.gerar_cns(1)], "SINDRAS_CNS", self.cofres["sindras_svc_tokenize"])[0].valor
        r = lib.detokenize([t], "SINDRAS_CNS", self.cofres["sindras_cns_3_left"])
        self.assertFalse(r[0].ok)
        self.assertEqual(r[0].categoria, "permissao")

    def test_credencial_errada_da_401(self):
        import fake_dados
        c = lib.Cofre(lib.transporte_http(self.srv.url, "sindras_total", "errada"), usuario="x", dormir=lambda s: None)
        with self.assertRaises(lib.ErroCofre) as cm:
            lib.detokenize(["1" * 11], "SINDRAS_CPF", c)
        self.assertEqual(cm.exception.categoria, "autenticacao")


FLUXO = AQUI / "fluxo-dev.sh"


@unittest.skipUnless(FLUXO.exists(), "fluxo-dev.sh ausente")
class TestFluxoDev(unittest.TestCase):
    """Prova com um stub de `ctvl` no PATH que `apply` sem --yes nunca chama `ctvl apply`."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.log = base / "chamadas.log"
        stub = base / "bin" / "ctvl"
        stub.parent.mkdir()
        stub.write_text(textwrap.dedent(f"""\
            #!/usr/bin/env bash
            echo "$*" >> "{self.log}"
            echo "(stub ctvl) $1"
            """))
        stub.chmod(0o755)
        envf = base / "sindras.env"
        envf.write_text("".join(f"CTVL_SINDRAS_{n}_PASSWORD=stub-{n}\n" for n in
                                ("SVC_TOKENIZE", "TOTAL", "CPF_3_LEFT_2_RIGHT", "CPF_0_LEFT_2_RIGHT", "CNS_3_LEFT", "CNS_0_LEFT_0_RIGHT")))
        raiz = base / "raiz"
        (raiz / "docs/tokenizacao-ctvl").mkdir(parents=True)
        (raiz / "docs/tokenizacao-ctvl/config-sindras-dev.yaml").write_text("# stub\n")
        self.env = {**os.environ, "SINDRAS_ROOT": str(raiz), "PATH": f"{stub.parent}:{os.environ['PATH']}", "SINDRAS_ENV": str(envf)}

    def tearDown(self):
        self.tmp.cleanup()

    def rodar(self, *args):
        return subprocess.run(["bash", str(FLUXO), *args], env=self.env, capture_output=True, text=True, timeout=60)

    def chamadas(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_sem_argumento_mostra_uso(self):
        r = self.rodar()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("Uso", r.stdout + r.stderr)

    def test_apply_sem_yes_so_planeja(self):
        r = self.rodar("apply")
        self.assertEqual(r.returncode, 0, r.stderr)
        cham = self.chamadas()
        self.assertTrue(any(c.startswith("plan dev") for c in cham), cham)
        self.assertFalse(any(c.startswith("apply") for c in cham), cham)

    def test_apply_com_yes_repassa_yes(self):
        r = self.rodar("apply", "--yes")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(any(c.startswith("apply dev") and "--yes" in c.split() for c in self.chamadas()))

    def test_habilitar_sem_yes_e_dry_run(self):
        r = self.rodar("habilitar", "sindras_cns_3_left")
        self.assertEqual(r.returncode, 0, r.stderr)
        cham = [c for c in self.chamadas() if c.startswith("enable-detokenize")]
        self.assertEqual(len(cham), 1)
        self.assertNotIn("--yes", cham[0].split())

    def test_habilitar_exige_usuario_mascarado_conhecido(self):
        r = self.rodar("habilitar", "outro_usuario", "--yes")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.chamadas(), [])

    def test_nao_imprime_senha(self):
        r = self.rodar("verificar")
        self.assertNotIn("stub-TOTAL", r.stdout + r.stderr)
        self.assertNotIn("stub-CNS", r.stdout + r.stderr)

    def test_env_ausente_falha_com_mensagem_curta(self):
        env = {**self.env, "SINDRAS_ENV": str(Path(self.tmp.name) / "nao-existe.env")}
        r = subprocess.run(["bash", str(FLUXO), "verificar"], env=env, capture_output=True, text=True, timeout=60)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("env", (r.stdout + r.stderr).lower())


if __name__ == "__main__":
    unittest.main()
