<div class="test-controls" {% if not blk.is_test %}style="display:none"{% endif %}>
    <div class="form-group label-floating">
        <input type="text" id="block-{{name}}-test_correct{{ lang_code_for_id }}" name="blocks[].test_correct{{ lang_code_with_dollar }}"
               class="input-block-level form-control" value="{{ blk.test_correct[lang_code]  }}"
               placeholder="{_ Feedback if correct _}">
        <label class="control-label">{_ Feedback if correct _}</label>
    </div>

    <div class="form-group label-floating">
        <input type="text" id="block-{{name}}-test_wrong{{ lang_code_for_id }}" name="blocks[].test_wrong{{ lang_code_with_dollar }}" 
               class="input-block-level form-control" value="{{ blk.test_wrong[lang_code]  }}"
               placeholder="{_ Feedback if wrong _}">
        <label class="control-label">{_ Feedback if wrong _}</label>
    </div>
</div>
