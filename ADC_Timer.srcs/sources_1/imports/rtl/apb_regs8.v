module apb_regs8 (
    input  wire       clk,
    input  wire       rst_n,

    // Bus APB Interface (1-cycle access)
    input  wire       psel,
    input  wire       penable,
    input  wire       pwrite,
    input  wire [3:0] paddr,
    input  wire [7:0] pwdata,
    output reg  [7:0] prdata,

    // Giao tiếp với Timer (timer8)
    output reg  [7:0] tmr_ctrl,
    output reg  [7:0] tmr_presc,
    output reg  [7:0] tmr_load,
    output reg  [7:0] tmr_cmp,
    input  wire [7:0] tmr_cnt,

    // Giao tiếp với ADC Controller (sar_adc_ctrl)
    output reg  [7:0] adc_ctrl,
    output reg  [7:0] adc_smp,
    output reg  [7:0] adc_div,
    output reg  [7:0] adc_thr_lo,
    output reg  [7:0] adc_thr_hi,
    input  wire [7:0] adc_stat,
    input  wire [7:0] adc_rch,

    // Giao tiếp với FIFO (sync_fifo)
    input  wire [7:0] adc_data_fifo,
    output wire       fifo_pop,

    // Quản lý Ngắt (IRQ)
    output reg  [7:0] irq_en,
    output reg  [7:0] irq_stat,
    input  wire [5:0] irq_events, // {trig_miss, fifo_ovr, adc_wd, adc_eoc, tmr_cmp, tmr_ovf}
    output wire       irq
);

    // 1. Tự động phát xung pop FIFO khi CPU đọc ADC_DATA (0xA)
    assign fifo_pop = psel && penable && (!pwrite) && (paddr == 4'hA);

    // 2. Đầu ra Ngắt IRQ gửi về CPU (bật khi có cờ ngắt & irq_en tương ứng)
    assign irq = |(irq_stat & irq_en);

    // 3. Ghi thanh ghi & Cập nhật cờ ngắt (Ưu tiên Hardware Event hơn W1C)
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmr_ctrl   <= 8'h00;
            tmr_presc  <= 8'h00;
            tmr_load   <= 8'hFF;
            tmr_cmp    <= 8'h80;
            adc_ctrl   <= 8'h00;
            adc_smp    <= 8'h04;
            adc_div    <= 8'h00;
            adc_thr_lo <= 8'h00;
            adc_thr_hi <= 8'hFF;
            irq_en     <= 8'h00;
            irq_stat   <= 8'h00;
        end else begin
            // Cập nhật cờ ngắt từ sự kiện phần cứng và xử lý W1C từ CPU
            for (i = 0; i < 6; i = i + 1) begin
                if (irq_events[i]) begin
                    irq_stat[i] <= 1'b1; // Phần cứng set cờ ngắt
                end else if (psel && penable && pwrite && (paddr == 4'hE) && pwdata[i]) begin
                    irq_stat[i] <= 1'b0; // CPU ghi 1 để xóa (W1C)
                end
            end

            // Ghi các thanh ghi cấu hình RW từ CPU Bus
            if (psel && penable && pwrite) begin
                case (paddr)
                    4'h0: tmr_ctrl   <= pwdata;
                    4'h1: tmr_presc  <= pwdata;
                    4'h2: tmr_load   <= pwdata;
                    4'h3: tmr_cmp    <= pwdata;
                    4'h5: adc_ctrl   <= pwdata;
                    4'h6: adc_smp    <= pwdata;
                    4'h7: adc_div    <= pwdata;
                    4'h8: adc_thr_lo <= pwdata;
                    4'h9: adc_thr_hi <= pwdata;
                    4'hD: irq_en     <= pwdata;
                    default: ; // Thanh ghi RO hoặc W1C đã xử lý riêng
                endcase
            end else begin
                // Tự động xóa bit START (bit 1) của ADC_CTRL sau 1 chu kỳ kích hoạt
                adc_ctrl[6] <= 1'b0;
            end
        end
    end

    // 4. MUX Đọc thanh ghi (Read MUX)
    always @(*) begin
        case (paddr)
            4'h0: prdata = tmr_ctrl;
            4'h1: prdata = tmr_presc;
            4'h2: prdata = tmr_load;
            4'h3: prdata = tmr_cmp;
            4'h4: prdata = tmr_cnt;
            4'h5: prdata = adc_ctrl & 8'hFD; // START bit đọc ra luôn bằng 0
            4'h6: prdata = adc_smp;
            4'h7: prdata = adc_div;
            4'h8: prdata = adc_thr_lo;
            4'h9: prdata = adc_thr_hi;
            4'hA: prdata = adc_data_fifo;     // Đọc dữ liệu từ hàng đợi FIFO
            4'hB: prdata = adc_rch;           // Đọc kênh dữ liệu (không pop FIFO)
            4'hC: prdata = adc_stat;          // Đọc trạng thái ADC & FIFO level
            4'hD: prdata = irq_en;
            4'hE: prdata = irq_stat;
            4'hF: prdata = 8'hA8;             // ID cố định 0xA8
            default: prdata = 8'h00;
        endcase
    end

endmodule