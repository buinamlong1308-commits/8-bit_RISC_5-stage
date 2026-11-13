package adc_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ------------------------------------------------------------------
    // Item: một lần đo
    // ------------------------------------------------------------------
    class adc_item extends uvm_sequence_item;
        rand bit [1:0]  chan;
        rand bit [11:0] vin_mv;     // 0..3300 mV
        rand bit [7:0]  smp;
        rand bit [7:0]  div;

        constraint c_vin { vin_mv <= 12'd3300; }
        constraint c_smp { smp inside {[0:8]}; }
        constraint c_div { div inside {[0:3]}; }

        `uvm_object_utils(adc_item)

        function new(string name = "adc_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("ch%0d vin=%0d mV smp=%0d div=%0d", chan, vin_mv, smp, div);
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Driver
    // ------------------------------------------------------------------
    class adc_driver extends uvm_driver #(adc_item);
        `uvm_component_utils(adc_driver)

        virtual adc_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual adc_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface chua duoc set")
        endfunction

        task run_phase(uvm_phase phase);
            wait (vif.rst_n === 1'b1);
            repeat (2) @(negedge vif.clk);
            forever begin
                seq_item_port.get_next_item(req);
                drive(req);
                seq_item_port.item_done();
            end
        endtask

        task drive(adc_item t);
            int unsigned lat = 0;

            vif.vin_mv[t.chan] = t.vin_mv;
            vif.ch_in = t.chan;
            vif.smp   = t.smp;
            vif.div   = t.div;

            @(negedge vif.clk); vif.start = 1'b1;
            @(negedge vif.clk); vif.start = 1'b0;

            while (!vif.eoc && lat < 5000) begin
                @(negedge vif.clk);
                lat++;
            end
            if (lat >= 5000)
                `uvm_error("DRV", $sformatf("timeout cho eoc: %s", t.convert2string()))
            else
                `uvm_info("DRV", $sformatf("%s -> result=%0d (0x%02h), latency=%0d",
                                           t.convert2string(), vif.result, vif.result, lat), UVM_LOW)

            @(negedge vif.clk);      // nghỉ 1 clock trước item kế tiếp
        endtask
    endclass

    // ------------------------------------------------------------------
    // Sequencer: không cần code riêng
    // ------------------------------------------------------------------
    typedef uvm_sequencer #(adc_item) adc_sequencer;
    // ------------------------------------------------------------------
    // Transaction quan sát được (đầu ra của monitor)
    // ------------------------------------------------------------------
    class adc_txn extends uvm_object;
        bit [1:0]    chan;
        bit [11:0]   vin_mv;
        bit [7:0]    smp, div;
        bit [7:0]    result;
        int unsigned latency;       // số clock từ start được nhận đến eoc

        `uvm_object_utils(adc_txn)

        function new(string name = "adc_txn");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("ch%0d vin=%0d mV smp=%0d div=%0d -> result=%0d (0x%02h) latency=%0d",
                             chan, vin_mv, smp, div, result, result, latency);
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Monitor: chỉ quan sát, không lái tín hiệu
    // ------------------------------------------------------------------
    class adc_monitor extends uvm_monitor;
        `uvm_component_utils(adc_monitor)

        virtual adc_if vif;
        uvm_analysis_port #(adc_txn) ap;
        int unsigned n_txn = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db#(virtual adc_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface chua duoc set")
        endfunction

        task run_phase(uvm_phase phase);
            wait (vif.rst_n === 1'b1);
            forever begin
                @(posedge vif.clk);
                // lệnh start được DUT nhận: start=1 khi ADC đang rảnh
                if (vif.start === 1'b1 && vif.busy === 1'b0 && vif.en === 1'b1)
                    collect();
            end
        endtask

        task collect();
            adc_txn      t = adc_txn::type_id::create("t");
            int unsigned c = 0;
            bit          done = 1'b0;

            // cấu hình tại thời điểm start (driver đã đặt từ trước)
            t.chan   = vif.ch_in;
            t.vin_mv = vif.vin_mv[vif.ch_in];
            t.smp    = vif.smp;
            t.div    = vif.div;

            while (!done && c < 5000) begin
                @(posedge vif.clk);
                c++;
                if (!vif.en) begin
                    `uvm_warning("MON", "en=0 giua chung: chuyen doi bi huy, khong co ket qua")
                    return;
                end
                if (vif.eoc === 1'b1) begin
                    t.result  = vif.result;
                    t.latency = c - 1;      // eoc được set ở cạnh liền trước cạnh đọc
                    done = 1'b1;
                end
            end

            if (!done) begin
                `uvm_error("MON", "timeout cho eoc")
            end else begin
                n_txn++;
                `uvm_info("MON", t.convert2string(), UVM_LOW)
                ap.write(t);
            end
        endtask
    endclass

    // ------------------------------------------------------------------
    // Sequences
    // ------------------------------------------------------------------
    class adc_corner_seq extends uvm_sequence #(adc_item);
        `uvm_object_utils(adc_corner_seq)

        function new(string name = "adc_corner_seq");
            super.new(name);
        endfunction

        task body();
            int unsigned vals[] = '{0, 5, 1111, 1650, 2000, 3200, 3290, 3300};
            foreach (vals[i]) begin
                int unsigned v = vals[i];
                req = adc_item::type_id::create("req");
                start_item(req);
                if (!req.randomize() with { vin_mv == local::v; })
                    `uvm_fatal("SEQ", "randomize that bai")
                finish_item(req);
            end
        endtask
    endclass

    class adc_rand_seq extends uvm_sequence #(adc_item);
        `uvm_object_utils(adc_rand_seq)

        int unsigned n = 10;

        function new(string name = "adc_rand_seq");
            super.new(name);
        endfunction

        task body();
            repeat (n) begin
                req = adc_item::type_id::create("req");
                start_item(req);
                if (!req.randomize())
                    `uvm_fatal("SEQ", "randomize that bai")
                finish_item(req);
            end
        endtask
    endclass

    // ------------------------------------------------------------------
    // Scoreboard: tự tính đáp án đúng và so sánh
    // ------------------------------------------------------------------
    class adc_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(adc_scoreboard)

        uvm_analysis_imp #(adc_txn, adc_scoreboard) imp;
        int unsigned n_checked = 0;
        int unsigned n_fail    = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            imp = new("imp", this);
        endfunction

        function void write(adc_txn t);
            int unsigned exp_code, exp_lat;

            exp_code = (int'(t.vin_mv) * 256) / 3300;
            if (exp_code > 255) exp_code = 255;
            exp_lat  = (t.smp + 9) * (t.div + 1);

            n_checked++;
            if (t.result !== exp_code[7:0]) begin
                n_fail++;
                `uvm_error("SB", $sformatf("SAI MA: %s | mong doi %0d", t.convert2string(), exp_code))
            end
            if (t.latency != exp_lat) begin
                n_fail++;
                `uvm_error("SB", $sformatf("SAI DO TRE: %s | mong doi %0d", t.convert2string(), exp_lat))
            end
        endfunction

        function void report_phase(uvm_phase phase);
            if (n_checked == 0)
                `uvm_error("SB", "khong cham duoc giao dich nao (test rong?)")
            else if (n_fail == 0)
                `uvm_info("SB", $sformatf("PASS: %0d giao dich dung", n_checked), UVM_LOW)
            else
                `uvm_info("SB", $sformatf("FAIL: %0d loi trong %0d giao dich", n_fail, n_checked), UVM_LOW)
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Agent
    // ------------------------------------------------------------------
    class adc_agent extends uvm_agent;
        `uvm_component_utils(adc_agent)

        adc_sequencer sqr;
        adc_driver    drv;
        adc_monitor   mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sqr = adc_sequencer::type_id::create("sqr", this);
            drv = adc_driver::type_id::create("drv", this);
            mon = adc_monitor::type_id::create("mon", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Env
    // ------------------------------------------------------------------
    class adc_env extends uvm_env;
        `uvm_component_utils(adc_env)

        adc_agent      agt;
        adc_scoreboard sb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agt = adc_agent::type_id::create("agt", this);
            sb  = adc_scoreboard::type_id::create("sb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agt.mon.ap.connect(sb.imp);
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------
    class adc_smoke_test extends uvm_test;
        `uvm_component_utils(adc_smoke_test)

        virtual adc_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual adc_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface chua duoc set")
        endfunction

        task run_phase(uvm_phase phase);
            int unsigned lat;
            phase.raise_objection(this);
            wait (vif.rst_n === 1'b1);
            repeat (2) @(negedge vif.clk);
            vif.vin_mv[2] = 12'd1111;
            vif.ch_in = 2'd2; vif.smp = 8'd2; vif.div = 8'd0;
            @(negedge vif.clk); vif.start = 1'b1;
            @(negedge vif.clk); vif.start = 1'b0;
            lat = 0;
            while (!vif.eoc && lat < 1000) begin @(negedge vif.clk); lat++; end
            `uvm_info("SMOKE", $sformatf("result=%0d latency=%0d", vif.result, lat), UVM_LOW)
            if (vif.result !== 8'd86 || lat != 11) `uvm_error("SMOKE", "mong doi 86 va 11 clock")
            phase.drop_objection(this);
        endtask
    endclass

    
            class adc_test extends uvm_test;
        `uvm_component_utils(adc_test)

        adc_env        env;
        virtual adc_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual adc_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "virtual interface chua duoc set")
            env = adc_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            adc_corner_seq cseq = adc_corner_seq::type_id::create("cseq");
            adc_rand_seq   rseq = adc_rand_seq::type_id::create("rseq");
            rseq.n = 20;

            phase.raise_objection(this);
            cseq.start(env.agt.sqr);
            rseq.start(env.agt.sqr);
            repeat (5) @(negedge vif.clk);       // chờ monitor và scoreboard xử lý nốt

            if (env.sb.n_checked != 8 + rseq.n)
                `uvm_error("TEST", $sformatf("scoreboard cham %0d giao dich, mong doi %0d",
                                             env.sb.n_checked, 8 + rseq.n))
            phase.drop_objection(this);
        endtask
    endclass
    
        localparam int N_TIMER_CORNERS = 6;

    // ------------------------------------------------------------------
    // Timer: item
    // ------------------------------------------------------------------
    class timer_item extends uvm_sequence_item;
        rand bit [7:0]      presc, load, cmp_th;
        rand int unsigned   run_clks;

        constraint c_presc { presc  inside {[0:7]};  }
        constraint c_load  { load   inside {[0:15]}; }
        constraint c_cmp   { cmp_th inside {[0:18]}; }   // có cả trường hợp cmp > load
        constraint c_run   { run_clks inside {[40:600]}; }

        `uvm_object_utils(timer_item)

        function new(string name = "timer_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("presc=%0d load=%0d cmp=%0d run=%0d", presc, load, cmp_th, run_clks);
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Timer: transaction quan sát được
    // ------------------------------------------------------------------
    class timer_txn extends uvm_object;
        bit [7:0] presc, load, cmp_th;
        int       run_clks;
        int       ovf_idx[$];
        int       cmp_idx[$];
        int       pwm_hi;
        bit [7:0] cnt_after;
        bit       pwm_after;

        `uvm_object_utils(timer_txn)

        function new(string name = "timer_txn");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("presc=%0d load=%0d cmp=%0d run=%0d | ovf=%0d cmp_pulses=%0d pwm_hi=%0d",
                             presc, load, cmp_th, run_clks, ovf_idx.size(), cmp_idx.size(), pwm_hi);
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Timer: driver
    // ------------------------------------------------------------------
    class timer_driver extends uvm_driver #(timer_item);
        `uvm_component_utils(timer_driver)

        virtual timer_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual timer_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "timer_if chua duoc set")
        endfunction

        task run_phase(uvm_phase phase);
            wait (vif.rst_n === 1'b1);
            repeat (2) @(negedge vif.clk);
            forever begin
                seq_item_port.get_next_item(req);
                drive(req);
                seq_item_port.item_done();
            end
        endtask

        task drive(timer_item t);
            vif.presc  = t.presc;
            vif.load   = t.load;
            vif.cmp_th = t.cmp_th;
            @(negedge vif.clk); vif.en = 1'b1;
            repeat (t.run_clks) @(negedge vif.clk);
            vif.en = 1'b0;
            repeat (4) @(negedge vif.clk);     // chừa chỗ cho monitor đọc trạng thái sau khi tắt
        endtask
    endclass

    typedef uvm_sequencer #(timer_item) timer_sequencer;

    // ------------------------------------------------------------------
    // Timer: monitor
    // ------------------------------------------------------------------
    class timer_monitor extends uvm_monitor;
        `uvm_component_utils(timer_monitor)

        virtual timer_if vif;
        uvm_analysis_port #(timer_txn) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db#(virtual timer_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "timer_if chua duoc set")
        endfunction

        task run_phase(uvm_phase phase);
            wait (vif.rst_n === 1'b1);
            forever begin
                @(posedge vif.clk);
                if (vif.en === 1'b1) collect();     // đây là cạnh đầu tiên có EN=1 (chỉ số 1)
            end
        endtask

        task collect();
            timer_txn t = timer_txn::type_id::create("t");
            int i = 1;

            t.presc  = vif.presc;
            t.load   = vif.load;
            t.cmp_th = vif.cmp_th;

            forever begin
                // giá trị đọc ở cạnh lên là giá trị được set ở cạnh liền trước
                if (vif.ovf       === 1'b1) t.ovf_idx.push_back(i);
                if (vif.cmp_pulse === 1'b1) t.cmp_idx.push_back(i);
                if (vif.en !== 1'b1) break;                 // đã tắt EN
                if (vif.pwm === 1'b1) t.pwm_hi++;
                t.run_clks = i;
                if (i > 100000) begin
                    `uvm_error("MON", "timeout: EN khong ha xuong")
                    return;
                end
                @(posedge vif.clk);
                i++;
            end

            @(posedge vif.clk);                              // một cạnh sau khi EN=0
            t.cnt_after = vif.cnt;
            t.pwm_after = vif.pwm;

            `uvm_info("MON", t.convert2string(), UVM_LOW)
            ap.write(t);
        endtask
    endclass

    // ------------------------------------------------------------------
    // Timer: scoreboard
    // ------------------------------------------------------------------
    class timer_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(timer_scoreboard)

        uvm_analysis_imp #(timer_txn, timer_scoreboard) imp;
        int unsigned n_checked = 0;
        int unsigned n_fail    = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            imp = new("imp", this);
        endfunction

        function automatic bit same_q(int a[$], int b[$]);
            if (a.size() != b.size()) return 1'b0;
            foreach (a[k]) if (a[k] != b[k]) return 1'b0;
            return 1'b1;
        endfunction

        function void write(timer_txn t);
            int exp_ovf[$], exp_cmp[$];
            int P, L, C, R, hi;

            P = int'(t.presc) + 1;
            L = int'(t.load)  + 1;
            C = int'(t.cmp_th);
            R = t.run_clks;
            hi = 0;

            for (int q = 1; ; q++) begin
                int i = q * L * P + 1;
                if (i > R + 1) break;
                exp_ovf.push_back(i);
            end
            if (C <= int'(t.load)) begin
                for (int q = 0; ; q++) begin
                    int i = (C + 1 + q * L) * P + 1;
                    if (i > R + 1) break;
                    exp_cmp.push_back(i);
                end
            end
            for (int i = 1; i <= R; i++)
                if ((((i - 1) / P) % L) < C) hi++;

            n_checked++;
            if (!same_q(exp_ovf, t.ovf_idx)) begin
                n_fail++;
                `uvm_error("SB", $sformatf("SAI XUNG OVF: %s | mong doi %0d xung, thay %0d",
                                           t.convert2string(), exp_ovf.size(), t.ovf_idx.size()))
            end
            if (!same_q(exp_cmp, t.cmp_idx)) begin
                n_fail++;
                `uvm_error("SB", $sformatf("SAI XUNG CMP: %s | mong doi %0d xung, thay %0d",
                                           t.convert2string(), exp_cmp.size(), t.cmp_idx.size()))
            end
            if (t.pwm_hi != hi) begin
                n_fail++;
                `uvm_error("SB", $sformatf("SAI PWM: %s | mong doi pwm_hi=%0d", t.convert2string(), hi))
            end
            if (t.cnt_after !== 8'd0 || t.pwm_after !== 1'b0) begin
                n_fail++;
                `uvm_error("SB", $sformatf("EN=0 khong xoa: %s | cnt=%0d pwm=%0b",
                                           t.convert2string(), t.cnt_after, t.pwm_after))
            end
        endfunction

        function void report_phase(uvm_phase phase);
            if (n_checked == 0)
                `uvm_error("SB", "timer: khong cham duoc lan chay nao")
            else if (n_fail == 0)
                `uvm_info("SB", $sformatf("TIMER PASS: %0d lan chay dung", n_checked), UVM_LOW)
            else
                `uvm_info("SB", $sformatf("TIMER FAIL: %0d loi trong %0d lan chay", n_fail, n_checked), UVM_LOW)
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Timer: agent + env
    // ------------------------------------------------------------------
    class timer_agent extends uvm_agent;
        `uvm_component_utils(timer_agent)

        timer_sequencer sqr;
        timer_driver    drv;
        timer_monitor   mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sqr = timer_sequencer::type_id::create("sqr", this);
            drv = timer_driver::type_id::create("drv", this);
            mon = timer_monitor::type_id::create("mon", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    class timer_env extends uvm_env;
        `uvm_component_utils(timer_env)

        timer_agent      agt;
        timer_scoreboard sb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agt = timer_agent::type_id::create("agt", this);
            sb  = timer_scoreboard::type_id::create("sb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agt.mon.ap.connect(sb.imp);
        endfunction
    endclass

    // ------------------------------------------------------------------
    // Timer: sequences
    // ------------------------------------------------------------------
    class timer_corner_seq extends uvm_sequence #(timer_item);
        `uvm_object_utils(timer_corner_seq)

        function new(string name = "timer_corner_seq");
            super.new(name);
        endfunction

        task send(int p, int l, int c, int r);
            req = timer_item::type_id::create("req");
            start_item(req);
            if (!req.randomize() with { presc == p; load == l; cmp_th == c; run_clks == r; })
                `uvm_fatal("SEQ", "randomize that bai")
            finish_item(req);
        endtask

        task body();
            send(1, 4, 2, 100);     // ví dụ trong tài liệu: PRESC=1, LOAD=4, CMP=2
            send(0, 0, 0, 60);      // LOAD=0, prescaler tắt
            send(0, 3, 5, 80);      // CMP > LOAD: không có xung cmp, PWM luôn cao
            send(2, 4, 0, 120);     // CMP=0: PWM luôn thấp
            send(3, 1, 1, 90);
            send(7, 15, 8, 400);    // prescaler và load lớn
        endtask
    endclass

    class timer_rand_seq extends uvm_sequence #(timer_item);
        `uvm_object_utils(timer_rand_seq)

        int unsigned n = 20;

        function new(string name = "timer_rand_seq");
            super.new(name);
        endfunction

        task body();
            repeat (n) begin
                req = timer_item::type_id::create("req");
                start_item(req);
                if (!req.randomize()) `uvm_fatal("SEQ", "randomize that bai")
                finish_item(req);
            end
        endtask
    endclass

    // ------------------------------------------------------------------
    // Test tổng: ADC rồi timer
    // ------------------------------------------------------------------
    class all_test extends uvm_test;
        `uvm_component_utils(all_test)

        adc_env        aenv;
        timer_env      tenv;
        virtual adc_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual adc_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "adc_if chua duoc set")
            aenv = adc_env::type_id::create("aenv", this);
            tenv = timer_env::type_id::create("tenv", this);
        endfunction

        task run_phase(uvm_phase phase);
            adc_corner_seq   ac = adc_corner_seq::type_id::create("ac");
            adc_rand_seq     ar = adc_rand_seq::type_id::create("ar");
            timer_corner_seq tc = timer_corner_seq::type_id::create("tc");
            timer_rand_seq   tr = timer_rand_seq::type_id::create("tr");
            ar.n = 20;
            tr.n = 20;

            phase.raise_objection(this);
            ac.start(aenv.agt.sqr);
            ar.start(aenv.agt.sqr);
            tc.start(tenv.agt.sqr);
            tr.start(tenv.agt.sqr);
            repeat (10) @(negedge vif.clk);

            if (aenv.sb.n_checked != 8 + ar.n)
                `uvm_error("TEST", $sformatf("ADC cham %0d, mong doi %0d", aenv.sb.n_checked, 8 + ar.n))
            if (tenv.sb.n_checked != N_TIMER_CORNERS + tr.n)
                `uvm_error("TEST", $sformatf("Timer cham %0d, mong doi %0d", tenv.sb.n_checked, N_TIMER_CORNERS + tr.n))
            phase.drop_objection(this);
        endtask
    endclass
endpackage