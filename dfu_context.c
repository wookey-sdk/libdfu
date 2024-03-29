/*
 *
 * Copyright 2018 The wookey project team <wookey@ssi.gouv.fr>
 *   - Ryad     Benadjila
 *   - Arnauld  Michelizza
 *   - Mathieu  Renard
 *   - Philippe Thierry
 *   - Philippe Trebuchet
 *
 * This package is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * the Free Software Foundation; either version 2.1 of the License, or (at
 * ur option) any later version.
 *
 * This package is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
 * PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License along
 * with this package; if not, write to the Free Software Foundation, Inc., 51
 * Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
 *
 */

#include "autoconf.h"
#include "api/dfu.h"
#include "libc/string.h"
#include "libc/types.h"
#include "libc/sync.h"
#include "dfu_priv.h"
#include "libusbctrl.h"
#include "dfu_priv.h"
#include "dfu_context.h"


/*
 * The DFU stack context. This is a global variable, which means
 * that the DFU stack is not reentrant (not for dfu_context write access).
 * As most micro-controlers are not multicore based, this should not be
 * a problem.
 */
#ifndef __FRAMAC__
static dfu_context_t dfu_context = {0};
#endif

static dfu_context_t * const dfu_ctx = &dfu_context;


/*@
  @ assigns \nothing;
  @ ensures \result == &dfu_context;
 */
dfu_context_t * dfu_get_context(void)
{
    return dfu_ctx;
}
/* PMO   @ requires \separated(ctx, ctx->data_out_buffer + (0 .. ctx->data_out_length-1));*/

/*@
  @ requires \separated(
          (usbctrl_context_t *)ctx_list + (..),
          &num_ctx,  &ctx->block_in_progress, &ctx->block_size, 
	  &ctx->can_download, &ctx->can_upload, &ctx->current_block_offset, 
	  &ctx->data_in_buffer, &ctx->data_in_current_block_nb, &ctx->data_in_length, 
	  &ctx->data_in_nb_blocks, &ctx->data_out_buffer, &ctx->data_out_current_block_nb, 
	  &ctx->data_out_length, &ctx->data_out_nb_blocks, &ctx->data_to_load, 
	  &ctx->data_to_store, &ctx->detach_timeout_ms, &ctx->detach_timeout_start, 
	  &ctx->firmware_size, &ctx->flash_address, &ctx->poll_start, &ctx->poll_timeout_ms, 
	  &ctx->session_in_progress, &ctx->state, &ctx->status, &ctx->transfert_size);
  @ requires \valid(ctx);
  @ assigns ctx->block_in_progress, ctx->session_in_progress, ctx->status, ctx->state, ctx->data_out_buffer, ctx->data_in_buffer, ctx->data_out_current_block_nb, ctx->data_out_nb_blocks, ctx->data_out_length, ctx->data_in_nb_blocks, ctx-> data_in_current_block_nb, ctx->data_in_length, ctx->flash_address, ctx->detach_timeout_ms, ctx->detach_timeout_start, ctx->poll_timeout_ms, ctx->poll_start, ctx->block_size, ctx->transfert_size, ctx->firmware_size, ctx->current_block_offset, ctx->data_to_store, ctx->data_to_load, ctx->can_download, ctx->can_upload, *((char*)&ctx->iface+ (0 .. sizeof(usbctrl_interface_t) -1)) ;
 @*/
void dfu_init_context(dfu_context_t *ctx)
{
    uint16_t transfert_size = ctx->transfert_size != 0 ? ctx->transfert_size : 0;
    uint8_t  **buffer = ctx->data_out_buffer != NULL ? ctx->data_out_buffer : 0;
    uint32_t  buffer_len = ctx->data_out_length != 0 ? ctx->data_out_length : 0;

    /* @ assert buffer != NULL ==> \valid(buffer+(0..buffer_len-1)); */
    ctx->block_in_progress = 0;
    ctx->session_in_progress = 0;
    ctx->status = OK;
    ctx->state = DFUIDLE;
    ctx->data_out_buffer = buffer;
    ctx->data_out_current_block_nb = 0;
    ctx->data_out_nb_blocks = 0;
    ctx->data_out_length = buffer_len;
    ctx->data_in_buffer = (uint8_t**)buffer;
    ctx->data_in_nb_blocks = 0;
    ctx->data_in_current_block_nb = 0;
    ctx->data_in_length = 0;
    ctx->flash_address = 0x80000000;
    ctx->detach_timeout_ms = MAX_TIME_DETACH;
    ctx->detach_timeout_start = 0;
    ctx->poll_timeout_ms = MAX_POLL_TIMEOUT;
    ctx->poll_start = 0;
    ctx->block_size = transfert_size;
    ctx->transfert_size = transfert_size;
    ctx->firmware_size = 0;
    ctx->current_block_offset = 0;
    ctx->data_to_store = false;
    ctx->data_to_load  = false;
#if CONFIG_USR_LIB_DFU_CAN_DOWNLOAD
    ctx->can_download = true;
#else
    ctx->can_download = false;
#endif
#if CONFIG_USR_LIB_DFU_CAN_UPLOAD
    ctx->can_upload = true;
#else
    ctx->can_upload = false;
#endif

    memset((void*)&ctx->iface, 0x0, sizeof(usbctrl_interface_t));
    request_data_membarrier();
}


