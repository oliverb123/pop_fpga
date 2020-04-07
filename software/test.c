#include "xparameters.h"
#include "inttypes.h"

/*
A simple test script and driver for the FPGA hardware. Used to benchmark
performance vs. a microblaze core. Change the define below depending on
your hardware platform.
*/

#define ENCODER_ADDR XPAR_LVSS_ENCODER_BACKREF_0_BASEADDR

//An extremely simple driver for the accelerator core
uint32_t test_core(char *in, uint32_t in_len, char *out){
	uint32_t out_len = 0;
	volatile uint32_t *encoder = (uint32_t*)ENCODER_ADDR;
	uint32_t padded_len = in_len + 14;
	int i;
	for(i = 0; i < 14; i++){
		*encoder = in[i];//Fill the encoder buffer with valid data
	}
	while(i < padded_len){
		*encoder = i < in_len ? i<<16 | (uint32_t)in[i] : 0x0000;//Push a byte in, padding the end of the string with null char
		uint32_t res = *encoder;//Read result from core for that byte
		uint32_t skip_len = res>>12;//bits 12 to 15 are length of substitution
		if(skip_len > 1){
			out[out_len++] = (char)(res>>8);
			out[out_len++] = (char)res;
			while(--skip_len > 0 && i < padded_len){
				i++;
				*encoder = i < in_len ? i<<16 | (uint32_t)in[i] : 0x0000;
			}
			i++;
		} else {
			out[out_len++] = in[i-14];
			i++;
		}
	}
	*encoder = 0x100;//Software reset the encoder
	return(out_len);
}

//The equivalent algorithm implemented relatively naively
uint16_t test_software(char *data_in, uint32_t in_len, char *data_out){
	uint32_t out_len = 0;
	uint32_t i = 0;//Current byte being substituted
	while(i < in_len){
		uint16_t cur_skip_pos = i-1;//position of current substitution
		uint8_t best_skip_len = 0;//length of best sub
		uint16_t best_skip_pos = 0;//position of best sub
		while(cur_skip_pos > 0 &&//We haven't walked off the end of the valid data
			  i - cur_skip_pos < 4096 &&//We haven't walked off the end of the window
			  best_skip_len < 15//We haven't found an optimal substitution
		) {
			uint8_t cur_skip_len = 0;
			for(uint32_t j = 0;//Iterator used to represent lookahead buffer
				j < 15 &&//15 byte lookahead buffer
				cur_skip_pos + j < i &&//don't count bytes in the lookahead buffer as part of the window
				i + j < in_len;//Don't walk off the end of the input
				j++
			){
				if(data_in[cur_skip_pos + j] != data_in[i+j]){
					break;
				} else {
					cur_skip_len += 1;
				}
			}
			if(cur_skip_len > best_skip_len){
				best_skip_len = cur_skip_len;
				best_skip_pos = cur_skip_pos;
			}
			cur_skip_pos--;
		}
		if(best_skip_len > 1){
			data_out[out_len++] = ((char)(best_skip_len<<4)) | ((char)(best_skip_pos>>8));
			data_out[out_len++] = (char)best_skip_pos;
			i += best_skip_len-1;
		} else {
			data_out[out_len++] = data_in[i];
		}
		i++;
	}
	return(out_len);
}

int main(){
//The input data must be padded with 15 null bytes to account for buffer architecture
	char in_data[36] = "This test is testing the encoder!!!!";
	uint32_t in_len = 36;//Including the null bytes of padding
	char out_data[36] = {0};//Maximum length of output data is the same as input data
	uint32_t out_len = 0;
	out_len = test_core(in_data, in_len, out_data);
//Push the compressed data to the axi bus to make verification easier
	uint32_t *encoder = (uint32_t*)ENCODER_ADDR;
	*encoder = out_len;//Push the encoded length
	for(uint32_t i = 0; i < out_len; i++){
		*encoder = (i<<16) | out_data[i];
	}
	for(uint32_t i = 0; i < 35; i++){
		out_data[i] = 0;//Clear output buffer in preparation for software test
	}
//Run software test
	out_len = test_software(in_data, in_len, out_data);
	//Push the compressed data to the axi bus to make verification easier
	*encoder = out_len;
	for(uint32_t i = 0; i < out_len; i++){
		*encoder = out_data[i];
	}
}
