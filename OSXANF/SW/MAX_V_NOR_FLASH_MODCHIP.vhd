----------------------------------------------------------------------
----                                                              ----
---- LPC PERIPHERAL INTERFACE FOR LPC FLASH DEVICES               ----
----                                                              ----
---- MAX_V_NOR_FLASH_MODCHIP.vhd                                  ----
----                                                              ----
----                                                              ----
---- Description:                                                 ----
---- Translate the addressing scheme between an LPC host and an   ----
---- LPC peripheral. At the moment, it only supports LPC Memory   ----
---- Read/Write between an LPC host and the follwing NOR flash    ----
---- devices:							  ----
----      SST39VF1681                                             ----
----      SST39VF1682                                             ----
----                                                              ----
----                                                              ----
----                                                              ----
---- Author(s):                                                   ----
----     - Aghogho Obi, one_eyed_monk on ASSEMBLERGAMES.COM       ----
----                                                              ----
----------------------------------------------------------------------
----                                                              ----
---- Copyright (C) 2017 Aghogho Obi                               ----
----                                                              ----
---- This source file may be used and distributed without         ----
---- restriction provided that this copyright statement is not    ----
---- removed from the file and that any derivative work contains  ----
---- the original copyright notice and the associated disclaimer. ----
----                                                              ----
---- This source code is free software: you can redistribute it   ----
---- and/or modify it under the terms of the GNU General Public   ----
---- License as published by the Free Software Foundation,either  ----
---- version 3 of the License, or (at your option) any later      ----
---- version.                                                     ----
----                                                              ----
---- This source is distributed in the hope that it will be       ----
---- useful, but WITHOUT ANY WARRANTY; without even the implied   ----
---- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ----
---- PURPOSE. See the GNU General Public License for more         ----
---- details.                                                     ----
----                                                              ----
---- You should have received a copy of the GNU General Public    ----
---- License along with this source; if not, download and see it  ----
---- from <http://www.gnu.org/licenses/>                          ----
----                                                              ----
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity MAX_V_NOR_FLASH_MODCHIP is
    Port 
	 ( 
		CLK_50MHZ 	: IN  STD_LOGIC;
		LEDS 		: OUT STD_LOGIC_VECTOR (2 DOWNTO 0);
		
		-- LPC IO
		LCLK_i      	: IN STD_LOGIC ;
		LRST_i      	: IN STD_LOGIC ;
		LAD_io      	: INOUT STD_LOGIC_VECTOR ( 3 DOWNTO 0 );
		
		-- IO for BANK SWITCHING
		BNK		: IN STD_LOGIC_VECTOR (2 DOWNTO 0);

		-- NOR FLASH IO		
		ADDR_o      	: OUT STD_LOGIC_VECTOR (20 DOWNTO 0);
		D0_io		: INOUT STD_LOGIC_VECTOR (7 DOWNTO 0);	
		nCE_o		: OUT STD_LOGIC;
		nOE_o		: OUT STD_LOGIC;
		nWE_o		: OUT STD_LOGIC
	);
end MAX_V_NOR_FLASH_MODCHIP;

architecture MAX_V_NOR_FLASH_MODCHIP_arch of MAX_V_NOR_FLASH_MODCHIP is
	
	-- LPC BUS STATES for memory IO. Will need to include other states to
	-- support other LPC transactions. 
	type LPC_TYPE is 
	(
		START, 
		CYCTYPE_DIR, 
		ADDR1, 
		ADDR2, 
		ADDR3, 
		ADDR4, 
		ADDR5, 
		ADDR6, 
		ADDR7, 
		ADDR8, 
		TAR1, 
		TAR2, 
		SYNC, 
		DATA1, 
		DATA2,
		DATA3,
		DATA4,
		TAR3, 
		TAR4
	);

	signal LPC_STATE	: LPC_TYPE 	:= START;
	signal count 		: STD_LOGIC_VECTOR (24 downto 0) := (others => '0');
	signal rRW		   : STD_LOGIC := '1';
	
	signal ADDR       : STD_LOGIC_VECTOR (20 DOWNTO 0) := (others => '0');
	signal D0			: STD_LOGIC_VECTOR (7 DOWNTO 0) := (others => '0');
	signal nCE		   : STD_LOGIC := '1';
	signal nOE		   : STD_LOGIC := '1';
	signal nWE		   : STD_LOGIC := '1';
	
begin
	-- Control LED IO with counter pattern
	LEDS <= NOT count(24 downto 22);
	
	-- Generate a counter for HW debug purposes
	process (CLK_50MHZ)
	begin
		if RISING_EDGE(CLK_50MHZ) then
			count <= count + 1;
		end if;
	end process;
	
	-- Connections to NOR flash
	nWE_o <= nWE;
	nCE_o <= nCE;
	nOE_o <= nOE;
	ADDR_o <= ADDR;
	
	-- Control NOR flash bi-directional IO
	D0_io  <= D0 when rRW = '1' else "ZZZZZZZZ";

	-- Provide the appropriate connection to the LPC bus master
	LAD_io <= "0000" when LPC_STATE = SYNC  else
		D0_io(3 downto 0) when LPC_STATE = DATA1 else 
		D0_io(7 downto 4) when LPC_STATE = DATA2 else 
		"ZZZZ";

	-- LPC Device State machine, see the Intel LPC Specifications for details
	process(LRST_i, LCLK_i)
	begin
		if (LRST_i = '0') then
	
			rRW <= '1';
			nCE <= '1';
			nOE <= '1';
			nWE <= '1';
			
			D0 <= (others => '0');
			ADDR <= (others => '0');

			LPC_STATE <= START;

		elsif rising_edge(LCLK_i) then
					  
			case LPC_STATE is
			
				when START =>

					if LAD_io = "0000" then
						LPC_STATE <= CYCTYPE_DIR;
					end if;
				
				when CYCTYPE_DIR =>

					if LAD_io(3 downto 2) = "01" then
						rRW <= LAD_io(1);
						LPC_STATE <= ADDR1;
					else
						LPC_STATE <= START;
					end if;				
										
				when ADDR1 =>
                    
					LPC_STATE <= ADDR2;
							
				when ADDR2 =>	
			
					LPC_STATE <= ADDR3;
					
				when ADDR3 =>	
				
					-- Pullup should be enabled on BNK IO, and BNK should be 
					-- grounded for BANK 0 (first 256k of NOR Flash).
					ADDR(20) <= BNK(2); 
                    
					LPC_STATE <= ADDR4;
					
				when ADDR4 =>	
			
					-- Pullup should be enabled on BNK IO, and BNK should be 
					-- grounded for BANK 0 (first 256k of NOR Flash).
					ADDR(19 downto 16) <= BNK(1 downto 0) & LAD_io(1 downto 0);

					LPC_STATE <= ADDR5;
					
				when ADDR5 =>	
			
               				ADDR(15 downto 12) <= LAD_io;
                    
					LPC_STATE <= ADDR6;
					
				when ADDR6 =>	
			
               				ADDR(11 downto 8) <= LAD_io;
                    
					LPC_STATE <= ADDR7;
					
				when ADDR7 =>
				
               				ADDR(7 downto 4) <= LAD_io;
                    
					LPC_STATE <= ADDR8;
					
				when ADDR8 =>
                    
               				ADDR(3 downto 0) <= LAD_io;
               
					if rRW = '0' then
						nOE <= '0';
						LPC_STATE <= TAR1;
					else
						nWE <= '0';
						LPC_STATE <= DATA3;
					end if;
					
				when TAR1 =>
					
					nCE <= '0';
					
					LPC_STATE <= TAR2;
					
				when TAR2 =>
					
					LPC_STATE <= SYNC;
					
				when SYNC =>
					
					if rRW = '0' then
						LPC_STATE <= DATA1;
					else
						LPC_STATE <= TAR3;
					end if;
					
				when DATA1 =>	
					
					LPC_STATE <= DATA2;
					
				when DATA2 =>
					
					LPC_STATE <= TAR3;
				
				when DATA3 =>
					
					D0(3 downto 0) <= LAD_io;
					
					LPC_STATE <= DATA4;
				
				when DATA4 =>
					
					D0(7 downto 4) <= LAD_io;
				
					LPC_STATE <= TAR1;
					
				when TAR3 =>
				
					nCE <= '1';
					
					LPC_STATE <= TAR4;
					
				when TAR4 =>
				
					rRW <= '1';
					nCE <= '1';
					nOE <= '1';
					nWE <= '1';
					
					LPC_STATE <= START;
				
			end case;
		end if;
	end process;

end MAX_V_NOR_FLASH_MODCHIP_arch;
