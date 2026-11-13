// timer_adc8_top.v - noi 4 khoi: apb_regs8, timer8, sar_adc_ctrl, sync_fifo
module timer_adc8_top (
    input  wire       clk,
    input  wire       rst_n,
    // bus APB 8 bit
    input  wire       psel,
    input  wire       penable,
    input  wire       pwrite,
    input  wire [3:0] paddr,
    input  wire [7:0] pwdata,
    output wire [7:0] prdata,
    output wire       irq,
    output wire       pwm_out,
    // front-end analog
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp
);
    wire       tmr_en, tmr_oneshot, tmr_ovf, tmr_cmpp;
    wire [7:0] tmr_presc, tmr_load, tmr_cmp, tmr_cnt;
    wire       adc_en, adc_start, adc_busy, adc_eoc;
    wire [1:0] adc_ch_sel;
    wire [7:0] adc_smp, adc_div, adc_result;
    wire       fifo_push, fifo_pop, fifo_empty, fifo_full, fifo_ovr;
    wire [9:0] fifo_din, fifo_dout;
    wire [3:0] fifo_level;

    apb_regs8 u_regs (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .irq(irq),
        .tmr_en(tmr_en), .tmr_oneshot(tmr_oneshot),
        .tmr_presc(tmr_presc), .tmr_load(tmr_load), .tmr_cmp(tmr_cmp),
        .tmr_cnt(tmr_cnt), .tmr_ovf(tmr_ovf), .tmr_cmpp(tmr_cmpp),
        .adc_en(adc_en), .adc_start(adc_start), .adc_ch_sel(adc_ch_sel),
        .adc_smp(adc_smp), .adc_div(adc_div),
        .adc_busy(adc_busy), .adc_eoc(adc_eoc),
        .adc_result(adc_result), .adc_ch_done(adc_ch),
        .fifo_push(fifo_push), .fifo_pop(fifo_pop), .fifo_din(fifo_din),
        .fifo_dout(fifo_dout), .fifo_level(fifo_level),
        .fifo_empty(fifo_empty), .fifo_full(fifo_full), .fifo_ovr(fifo_ovr)
    );

    timer8 u_timer (
        .clk(clk), .rst_n(rst_n), .en(tmr_en), .oneshot(tmr_oneshot),
        .presc(tmr_presc), .load(tmr_load), .cmp(tmr_cmp),
        .cnt(tmr_cnt), .ovf_pulse(tmr_ovf), .cmp_pulse(tmr_cmpp),
        .pwm_out(pwm_out)
    );

    sar_adc_ctrl u_adc (
        .clk(clk), .rst_n(rst_n), .en(adc_en), .start(adc_start),
        .ch_in(adc_ch_sel), .smp(adc_smp), .div(adc_div),
        .sample(adc_sample), .ch(adc_ch), .dac(adc_dac), .cmp(adc_cmp),
        .busy(adc_busy), .eoc(adc_eoc), .result(adc_result)
    );

    sync_fifo #(.W(10)) u_fifo (
        .clk(clk), .rst_n(rst_n),
        .push(fifo_push), .din(fifo_din), .pop(fifo_pop), .dout(fifo_dout),
        .level(fifo_level), .empty(fifo_empty), .full(fifo_full),
        .overflow(fifo_ovr)
    );
endmodule
