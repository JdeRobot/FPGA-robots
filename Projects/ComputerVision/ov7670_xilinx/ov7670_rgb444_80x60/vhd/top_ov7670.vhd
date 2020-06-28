--------------------------------------------------------------------------------
--   Felipe Machado Sanchez
--   Area de Tecnologia Electronica
--   Universidad Rey Juan Carlos
--   https://github.com/felipe-m
--
--   with debuging modules
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.ov7670_pkg.all;
use work.osc_pkg.all;

entity top_ov7670 is
    generic (
      g_debug_oscop : natural := 1;
      g_debug_7seg  : natural := 1;
      g_sample_freq : natural := 100_000_000
    );
    port ( 
      rst          : in    std_logic;
      clk          : in    std_logic;

      sw0_test_cmd : in    std_logic; --if '1', step by step SCCB instructions
      -- 0: RGB444, 1: RGB555, 2: RGB565, 3: YUV, 4(others): UV-Y
      -- always RGB444 for now
      --sw13_rgbmode : in    std_logic_vector(2 downto 0);
      sw4_test_osc : in    std_logic; --if '1' show oscilloscope
      sw56_regs    : in    std_logic_vector(1 downto 0); --choose regs sccb

      btnr_test    : in    std_logic; --if sw='1', SCCB sent one by one
      btnl_oscop   : in    std_logic; --restart capture oscilloscope(after trig

      ov7670_sioc  : out   std_logic;
      ov7670_siod  : out   std_logic;

      ov7670_rst_n : out   std_logic;
      ov7670_pwdn  : out   std_logic;
      ov7670_vsync : in    std_logic;
      ov7670_href  : in    std_logic;
      ov7670_pclk  : in    std_logic;
      ov7670_xclk  : out   std_logic;
      ov7670_d     : in    std_logic_vector(7 downto 0);

      led          : out    std_logic_vector(7 downto 0);

      vga_red      : out   std_logic_vector(3 downto 0);
      vga_green    : out   std_logic_vector(3 downto 0);
      vga_blue     : out   std_logic_vector(3 downto 0);
      vga_hsync    : out   std_logic;
      vga_vsync    : out   std_logic;

      anode7seg    : out   std_logic_vector(7 downto 0);
      seg7         : out   std_logic_vector(6 downto 0);
      
      btnc_resend  : in    std_logic
    );
end top_ov7670;

architecture struct of top_ov7670 is

   component debounce_1pulse
   port(
     rst       : in  std_logic;
     clk       : in  std_logic;
     sig_in    : in  std_logic;
     sig_out   : out std_logic
   );
   end component;

  component ov7670_top_ctrl is
    port(
      rst          : in  std_logic;        --reset, active high
      clk          : in  std_logic;        --fpga clock
      test_mode    : in  std_logic;        --if '1': in test mode
      test_send    : in  std_logic;        --in testmode, send 1 instruction
      sw_regs      : in  std_logic_vector(1 downto 0);
      resend       : in  std_logic;        --resend the sequence
      done         : out std_logic;        --all transmission done
      sclk         : out std_logic;        --sccb clock
      sdat_on      : out std_logic;        --transmitting serial ('1')
      --sdat_in    : in  std_logic;        --sccb serial data in
      sdat_out     : out std_logic;        --sccb serial data out, 3-state
      ov7670_rst_n : out std_logic;        --camera reset
      ov7670_clk   : out std_logic;        --camera system clock
      ov7670_pwdn  : out std_logic         --camera power down
    );
  end component;

  component frame_buffer
    port (
      clk   : in  std_logic;
      wea   : in  std_logic;
      addra : in  std_logic_vector(c_nb_img_pxls-1 downto 0);
      dina  : in  std_logic_vector(c_nb_buf-1 downto 0);
      addrb : in  std_logic_vector(c_nb_img_pxls-1 downto 0);
      doutb : out std_logic_vector(c_nb_buf-1 downto 0)
    );
  end component;

  component ov7670_capture
    port(
      rst   : in std_logic;
      clk   : in std_logic;
      pclk  : in std_logic;
      href  : in std_logic;
      vsync : in std_logic;
      sw13_rgbmode : in std_logic_vector (2 downto 0);
      dataout_test : out std_logic_vector(11 downto 0);
      led_test : out std_logic_vector(3 downto 0);
      data  : in std_logic_vector (7 downto 0);          
      addr  : out std_logic_vector(c_nb_img_pxls-1 downto 0);
      dout  : out std_logic_vector(c_nb_buf-1 downto 0);
      we    : out std_logic
    );
  end component;


   component vga_sync
   port(
      rst       : in std_logic;
      clk       : in std_logic;
      visible   : out std_logic;
      new_pxl   : out std_logic;
      hsync     : out std_logic;
      vsync     : out std_logic;
      col       : out unsigned(10-1 downto 0);
      row       : out unsigned(10-1 downto 0)
      );
   end component;

  component vga_display
    port (
      rst         : in std_logic;
      clk         : in std_logic;
      visible     : in std_logic;
      new_pxl     : in std_logic;
      hsync       : in std_logic;
      vsync       : in std_logic;
      rgbmode     : in std_logic;
      col         : in unsigned(10-1 downto 0);
      row         : in unsigned(10-1 downto 0);
      frame_pixel : in std_logic_vector(c_nb_buf-1 downto 0); 
      frame_addr  : out std_logic_vector(c_nb_img_pxls-1 downto 0);
      vga_red     : out std_logic_vector(3 downto 0);
      vga_green   : out std_logic_vector(3 downto 0);
      vga_blue    : out std_logic_vector(3 downto 0)
    );
  end component;

  -- for debuging: --------------------------
  component top_oscop is
    generic (
      g_clk_freq        : natural := 100000000;
      g_sample_freq     : natural :=  10000000
    );
    port (
      rst               : in  std_logic;
      clk               : in  std_logic;
     ------ signal to be sampled ----------
      signal2sample     : in  std_logic_vector(c_bt_ramword-1 downto 0);
      -- restart the capture (after trigger detection)
      restart_capture   : in  std_logic;
     ------ to vga ----------------------
      vga_out_red         : out  std_logic_vector (7 downto 0);
      vga_out_green       : out  std_logic_vector (7 downto 0);
      vga_out_blue        : out  std_logic_vector (7 downto 0);
      vga_hsynch          : out  std_logic;
      vga_vsynch          : out  std_logic
    );
  end component;

  component disp7seg_8dig is
    port (
      rst     : in  std_logic;
      clk     : in  std_logic;
      -- enables displays 
      en_disp : in  std_logic_vector(7 downto 0);
      num0    : in  std_logic_vector(3 downto 0);
      num1    : in  std_logic_vector(3 downto 0);
      num2    : in  std_logic_vector(3 downto 0);
      num3    : in  std_logic_vector(3 downto 0);
      num4    : in  std_logic_vector(3 downto 0);
      num5    : in  std_logic_vector(3 downto 0);
      num6    : in  std_logic_vector(3 downto 0);
      num7    : in  std_logic_vector(3 downto 0);
      seg     : out std_logic_vector(6 downto 0);
      anode   : out std_logic_vector(7 downto 0)
     );
  end component;

   signal vga_visible   : std_logic;
   signal vga_new_pxl   : std_logic;
   signal vga_col       : unsigned(10-1 downto 0);
   signal vga_row       : unsigned(10-1 downto 0);
   
   signal frame_addr  : std_logic_vector(c_nb_img_pxls-1 downto 0);
   signal frame_pixel : std_logic_vector(c_nb_buf-1 downto 0);

   signal capture_addr  : std_logic_vector(c_nb_img_pxls-1 downto 0);
   signal capture_data  : std_logic_vector(c_nb_buf-1 downto 0);
   signal capture_we    : std_logic;
   signal resend        : std_logic;
   signal config_finished : std_logic;

   signal sdat_on : std_logic;
   signal sdat_out: std_logic;  -- not making it INOUT, just out, but 3-state

   signal btnr_test_1p : std_logic;

   signal cnt_vsync_max_test : std_logic_vector(7 downto 0);
   signal en_seg7_disp : std_logic_vector(7 downto 0);
   signal seg7_num0 : std_logic_vector(3 downto 0);
   signal seg7_num1 : std_logic_vector(3 downto 0);
   signal seg7_num2 : std_logic_vector(3 downto 0);
   signal seg7_num3 : std_logic_vector(3 downto 0);
   signal seg7_num4 : std_logic_vector(3 downto 0);
   signal seg7_num5 : std_logic_vector(3 downto 0);
   signal seg7_num6 : std_logic_vector(3 downto 0);
   signal seg7_num7 : std_logic_vector(3 downto 0);


  signal ov_vga_red, ov_vga_green, ov_vga_blue: std_logic_vector(3 downto 0);
  signal ov_vga_hsync, ov_vga_vsync : std_logic;
  -- to test
  signal oscop_vga_red,oscop_vga_green,oscop_vga_blue: std_logic_vector(7 downto 0);
  signal oscop_vga_hsync, oscop_vga_vsync : std_logic;

  signal signal2sample : std_logic_vector (c_bt_ramword-1 downto 0);

  signal ov_capture_datatest : std_logic_vector(11 downto 0);

  -- it will be always "000" since we want RGB444 for this design
  signal sw13_rgbmode :  std_logic_vector(2 downto 0);
  signal rgbmode : std_logic;

begin

  sw13_rgbmode <= (others => '0');

  btn_deb1: debounce_1pulse
    port map(
      rst      => rst,
      clk      => clk,
      sig_in   => btnc_resend,
      sig_out  => resend
   );

  btn_deb2: debounce_1pulse
    port map(
      rst      => rst,
      clk      => clk,
      sig_in   => btnr_test,
      sig_out  => btnr_test_1p
   );


  I_vga: vga_sync
    port map(
      rst       => rst,
      clk       => clk,
      visible   => vga_visible,
      new_pxl   => vga_new_pxl,
      hsync     => ov_vga_hsync,
      vsync     => ov_vga_vsync,
      col       => vga_col,
      row       => vga_row
  );

  vga_hsync <= ov_vga_hsync when sw4_test_osc='0' else oscop_vga_hsync;
  vga_vsync <= ov_vga_vsync when sw4_test_osc='0' else oscop_vga_vsync;
  vga_red   <= ov_vga_red   when sw4_test_osc='0' else
               oscop_vga_red(7 downto 4);
  vga_green <= ov_vga_green when sw4_test_osc='0' else
               oscop_vga_green(7 downto 4);
  vga_blue  <= ov_vga_blue  when sw4_test_osc='0' else
               oscop_vga_blue(7 downto 4);

  rgbmode <= '1' when unsigned(sw13_rgbmode) < 3 else '0';

  I_ov_display: vga_display
    port map (
      rst         => rst,
      clk         => clk,
      visible     => vga_visible,
      new_pxl     => vga_new_pxl,
      hsync       => ov_vga_hsync,
      vsync       => ov_vga_vsync,
      rgbmode     => rgbmode,
      col         => vga_col,
      row         => vga_row,
      frame_pixel => frame_pixel,
      frame_addr  => frame_addr,
      vga_red     => ov_vga_red,
      vga_green   => ov_vga_green,
      vga_blue    => ov_vga_blue
    );


  fb : frame_buffer
    port map (
      clk   => clk,
      wea   => capture_we,
      addra => capture_addr,
      dina  => capture_data,
      addrb => frame_addr,
      doutb => frame_pixel
    );

  led(7 downto 4) <= "000" & config_finished;
  
  capture: ov7670_capture
    port map(
      rst   => rst,
      clk   => clk,
      pclk  => ov7670_pclk,
      vsync => ov7670_vsync,
      href  => ov7670_href,
      sw13_rgbmode => sw13_rgbmode,
      dataout_test => ov_capture_datatest,
      led_test  => led(3 downto 0),
      data  => ov7670_d,
      addr  => capture_addr,
      dout  => capture_data,
      we    => capture_we
    );
  
  controller: ov7670_top_ctrl
    port map(
      rst           => rst,
      clk           => clk,
      test_mode     => sw0_test_cmd,
      test_send     => btnr_test_1p,
      sw_regs       => sw56_regs,
      resend        => resend,
      done          => config_finished,
      sclk          => ov7670_sioc,
      sdat_on       => sdat_on,
      sdat_out      => sdat_out,
      ov7670_rst_n  => ov7670_rst_n,
      ov7670_clk    => ov7670_xclk,
      ov7670_pwdn   => ov7670_pwdn
    );

  ov7670_siod <= sdat_out when sdat_on = '1' else 'Z';

  signal2sample(0) <= ov7670_href;
  signal2sample(1) <= ov7670_vsync;

  signal2sample(2) <= ov7670_pclk;
  signal2sample(3) <= ov7670_d(4);

  signal2sample(4) <= ov7670_d(3);
  signal2sample(5) <= ov7670_d(2);

  signal2sample(6) <= ov7670_d(1);
  signal2sample(7) <= ov7670_d(0);
  
  g_osc: if g_debug_oscop = 1 generate
    i_osc: top_oscop
      generic map (
        g_clk_freq      => c_clk_freq,
        g_sample_freq   => g_sample_freq
      )
      port map(
        rst      => rst,
        clk      => clk,
        signal2sample  => signal2sample,
        -- restart the capture (after trigger detection)
        restart_capture => btnl_oscop,
       ------ to vga ----------------------
        vga_out_red     => oscop_vga_red,
        vga_out_green   => oscop_vga_green,
        vga_out_blue    => oscop_vga_blue,
        vga_hsynch      => oscop_vga_hsync,
        vga_vsynch      => oscop_vga_vsync
      );
  end generate g_osc;

  --seg7_num0 <= cnt_vsync_max_test(3 downto 0);
  --seg7_num1 <= cnt_vsync_max_test(7 downto 4);
  seg7_num0 <= ov_capture_datatest(3 downto 0);
  seg7_num1 <= ov_capture_datatest(7 downto 4);
  seg7_num2 <= ov_capture_datatest(11 downto 8);
  seg7_num3 <= (others => '0');
  seg7_num4 <= (others => '0');
  seg7_num5 <= (others => '0');
  seg7_num6 <= (others => '0');
  seg7_num7 <= (others => '0');
  en_seg7_disp <= "00000111";

  i_7seg: disp7seg_8dig
    port map (
      rst           => rst,
      clk           => clk,
      en_disp       => en_seg7_disp,
      num0          => seg7_num0,
      num1          => seg7_num1,
      num2          => seg7_num2,
      num3          => seg7_num3,
      num4          => seg7_num4,
      num5          => seg7_num5,
      num6          => seg7_num6,
      num7          => seg7_num7,
      seg           => seg7,
      anode         => anode7seg
     );

end struct;

