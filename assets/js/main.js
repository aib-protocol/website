/*
	Atmosphere by Pixelarity
	pixelarity.com | hello@pixelarity.com
	License: pixelarity.com/license
*/

(function($) {

	skel.breakpoints({
		xlarge:	'(max-width: 1680px)',
		large: '(max-width: 1280px)',
		medium: '(max-width: 980px)',
		small: '(max-width: 736px)',
		xsmall: '(max-width: 480px)',
		xxsmall: '(max-width: 360px)'
	});

	$(function() {

		var	$window = $(window),
			$body = $('body'),
			$header = $('#header'),
			$banner = $('#banner');

		// Disable animations/transitions until the page has loaded.
			$body.addClass('is-loading');

			$window.on('load', function() {
				window.setTimeout(function() {
					$body.removeClass('is-loading');
				}, 100);
			});

		// Fix: Placeholder polyfill.
			$('form').placeholder();

		// Prioritize "important" elements on medium.
			skel.on('+medium -medium', function() {
				$.prioritize(
					'.important\\28 medium\\29',
					skel.breakpoint('medium').active
				);
			});

		// Scrolly.
			$('.scrolly').scrolly({
				offset: function() {
					return $header.height();
				}
			});

		// Header.
			if (skel.vars.IEVersion < 9)
				$header.removeClass('alt');

			if ($banner.length > 0
			&&	$header.hasClass('alt')) {

				$window.on('resize', function() { $window.trigger('scroll'); });

				$banner.scrollex({
					bottom:		$header.outerHeight(),
					terminate:	function() { $header.removeClass('alt'); },
					enter:		function() { $header.addClass('alt'); },
					leave:		function() { $header.removeClass('alt'); }
				});

			}

		// Menu.
			var $menu = $('#menu');

			$menu._locked = false;

			$menu._lock = function() {

				if ($menu._locked)
					return false;

				$menu._locked = true;

				window.setTimeout(function() {
					$menu._locked = false;
				}, 350);

				return true;

			};

			$menu._show = function() {

				if ($menu._lock())
					$body.addClass('is-menu-visible');

			};

			$menu._hide = function() {

				if ($menu._lock())
					$body.removeClass('is-menu-visible');

			};

			$menu._toggle = function() {

				if ($menu._lock())
					$body.toggleClass('is-menu-visible');

			};

			$menu
				.appendTo($body)
				.on('click', function(event) {

					event.stopPropagation();

					// Hide.
						$menu._hide();

				})
				.find('.inner')
					.on('click', '.close', function(event) {

						event.preventDefault();
						event.stopPropagation();
						event.stopImmediatePropagation();

						// Hide.
							$menu._hide();

					})
					.on('click', function(event) {
						event.stopPropagation();
					})
					.on('click', 'a', function(event) {

						var href = $(this).attr('href');

						event.preventDefault();
						event.stopPropagation();

						// Hide.
							$menu._hide();

						// Redirect.
							window.setTimeout(function() {
								window.location.href = href;
							}, 350);

					});

			$body
				.on('click', 'a[href="#menu"]', function(event) {

					event.stopPropagation();
					event.preventDefault();

					// Toggle.
						$menu._toggle();

				})
				.on('keydown', function(event) {

					// Hide on escape.
						if (event.keyCode == 27)
							$menu._hide();

				});


	});

})(jQuery);

function countUpTo(count,selector,max)
    {
      console.log("count--> "+count);
        var div_by = count,
            speed = Math.round(count / div_by),
            $display = selector,
            run_count = 1,
            int_speed = 24;

        var int = setInterval(function() {
            if(run_count < div_by){
                $display.text(speed * run_count);
                run_count++;
            } else if(parseInt($display.text()) < count) {
                var curr_count = parseInt($display.text()) + 1;
                var text = "";
                if(max>99){
                     if(curr_count<10){
                        text = text+"00"+curr_count;
                    }
                    /*else if(curr_count < 100 && curr_count >9){
                        text = text+"0"+curr_count;
                    }*/
                    else{
                      text = curr_count;
                    }
                }else if(max<100 && max>9){
                     if(curr_count<10){
                        text = text+"00"+curr_count;
                    }
                   /*else if(curr_count < 100 && curr_count >9){
                        text = text+"0"+curr_count;
                    }*/
                    else{
                      text = curr_count;
                    }
                }else{
                      if(curr_count<10){
                        text = text+"00"+curr_count;
                    }
                   /*else if(curr_count < 100 && curr_count >9){
                        text = text+"0"+curr_count;
                    }*/
                    else{
                      text = curr_count;
                    }
                }
               
                $display.text(text);
            } else {
                clearInterval(int);
            }
        }, int_speed);
    }


var firstTime = true;
$(document).scroll(function(event) {



  var result = $('.count-timer').isOnScreen();

  if(result == true) {
      console.log("on screen");

      if(firstTime){
        firstTime = false;
            
          var count1 = $('.count1'),
            count2 = $('.count2'),
            count3 = $('.count3'),
            count4 = $('.count4'),
            count5 = $('.count5'),
            count6 = $('.count6')
            count1Num = count1.text(),
            count2Num = count2.text(),
            count3Num = count3.text(),
            count4Num = count4.text(),
            count5Num = count5.text(),
            count6Num = count6.text();

            var max = Math.max(parseInt(count1Num),parseInt(count2Num));
            max = Math.max(max,parseInt(count6Num));
            console.log(max);

            countUpTo(count1Num,count1,max);
            countUpTo(count2Num,count2,max);
            countUpTo(count3Num,count3,max);
            countUpTo(count4Num,count4,max);
            countUpTo(count5Num,count5,max);
            countUpTo(count6Num,count6,max);
      }

    }
});